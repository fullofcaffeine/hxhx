package backend.ocaml;

/**
	Native adapters for the standard `Reflect` and `Type` classes.

	Both classes are `extern` in the standard library: their static methods have
	no Haxe body, and each target supplies the implementation. Stage3 used to
	replace several of these calls, matched by the spelling `Reflect.hasField`
	or `Type.typeof` in the source, with fixed values: `hasField` was always
	`false`, `isFunction` always `true`, and `field`, `fields`, `getProperty`,
	`setProperty`, `getInstanceFields` and `typeof` returned an invalid value.
	The program compiled, then printed wrong results.

	This adapter selects a call by the declaration the typer chose (owner,
	method, and a bodiless standard declaration), never by the spelling. Every
	selected call goes to a runtime function from
	`packages/reflaxe.ocaml/std/runtime`. The runtime functions read the Stage3
	object layout: anonymous objects and class instances are both `HxAnon`
	records, and a class instance also carries its class descriptor. For example:

	```haxe
	final p = new Point(3, 4);
	Reflect.field(p, "x");     // HxReflect.field: 3
	Type.typeof({a: 1});       // ValueType.TObject
	```

	`Type.getClass`, `Type.getClassName`, and `Type.getEnumName` belong to
	`Stage3OcamlTypeQueries`, which renders them before this adapter runs.
	Methods that need class data that Stage3 does not register
	(`Type.getClassFields`, `Type.createInstance`, `Type.createEmptyInstance`)
	stop the build with a named error instead of returning an empty answer.
	Other `Reflect` and `Type` methods keep their existing bring-up module.
 */
private enum ReflectArgument {
	/** A `Dynamic` or type-parameter slot: the runtime receives the value as `Obj.t`. */
	Value;

	/** A `String` or `Array` slot whose Stage3 carrier is already the runtime's carrier. */
	Plain;
}

private typedef ReflectOperation = {
	final reference:String;
	final arguments:Array<ReflectArgument>;
}

private function reflectOperation(method:String):Null<ReflectOperation> {
	return switch method {
		case "field": {reference: "HxReflect.field", arguments: [Value, Plain]};
		case "hasField": {reference: "HxAnon.has", arguments: [Value, Plain]};
		case "setField": {reference: "HxAnon.set", arguments: [Value, Plain, Value]};
		case "getProperty": {reference: "HxReflect.getProperty", arguments: [Value, Plain]};
		case "setProperty": {reference: "HxReflect.setProperty", arguments: [Value, Plain, Value]};
		case "fields": {reference: "HxAnon.fields", arguments: [Value]};
		case "deleteField": {reference: "HxReflect.deleteField", arguments: [Value, Plain]};
		case "isFunction": {reference: "HxReflect.isFunction", arguments: [Value]};
		case "isObject": {reference: "HxReflect.isObject", arguments: [Value]};
		case "isEnumValue": {reference: "HxReflect.isEnumValue", arguments: [Value]};
		case "compare": {reference: "HxReflect.compare", arguments: [Value, Value]};
		case "compareMethods": {reference: "HxReflect.same_closure", arguments: [Value, Value]};
		case "callMethod": {reference: "HxReflect.callMethod", arguments: [Value, Value, Plain]};
		case "copy": {reference: "HxAnon.copy", arguments: [Value]};
		case _: null;
	};
}

private function typeOperation(method:String):Null<ReflectOperation> {
	return switch method {
		case "getSuperClass": {reference: "HxType.getSuperClass", arguments: [Value]};
		case "getInstanceFields": {reference: "HxType.getInstanceFields", arguments: [Value]};
		case "getEnum": {reference: "HxType.getEnum", arguments: [Value]};
		case "enumIndex": {reference: "HxType.enumIndex", arguments: [Value]};
		case "enumConstructor": {reference: "HxType.enumConstructor", arguments: [Value]};
		case "enumParameters": {reference: "HxType.enumParameters", arguments: [Value]};
		case "enumEq": {reference: "HxType.enumEq", arguments: [Value, Value]};
		case _: null;
	};
}

/** `Type` methods whose runtime answer depends on class data Stage3 never registers. */
private function unregisteredTypeData(method:String):Null<String> {
	return switch method {
		case "getClassFields": "static field lists";
		case "createInstance" | "createEmptyInstance": "class constructors";
		case _: null;
	};
}

/**
	`ValueType` constructors in declaration order. The index of each name is the
	number `HxReflect.value_type_index` returns for that kind of value.
 */
final VALUE_TYPE_CONSTRUCTORS = [
	"TNull",
	"TInt",
	"TFloat",
	"TBool",
	"TObject",
	"TFunction",
	"TClass",
	"TEnum",
	"TUnknown"
];

/** The canonical owner of the standard `ValueType` enum, declared in the `Type` module. */
final VALUE_TYPE_OWNER = "Type.ValueType";

typedef ReflectCallInput = {
	final call:TypedExactStaticCallSource.TypedExactStaticCall;
	final emit:HxExpr->String;

	/** The exact typed type of one argument of this call. */
	final argumentType:HxExpr->TyType;

	final names:Stage3OcamlLocalNames;

	/** The OCaml value for a `ValueType` constructor name and index, qualified for the current module. */
	final valueTypeConstructor:(String, Int) -> String;
}

/** Whether a typed call is a bodiless static method of the standard `Reflect` or `Type` class. */
function owns(call:TypedExactStaticCallSource.TypedExactStaticCall):Bool
	return !call.hasBody && (call.owner == "Reflect" || call.owner == "Type");

/**
	Render a typed standard `Reflect` or `Type` call through the runtime, or
	return null when this adapter does not own the call. Arguments are evaluated
	once, left to right, as in Haxe.
 */
function render(input:ReflectCallInput):Null<String> {
	final call = input.call;
	if (!owns(call))
		return null;
	if (call.owner == "Type") {
		final missing = unregisteredTypeData(call.method);
		if (missing != null)
			throw "stage3 emitter: Type." + call.method + " is not supported natively yet; Stage3 does not register " + missing;
		if (call.method == "typeof")
			return valueType(input);
	}
	final selected = call.owner == "Reflect" ? reflectOperation(call.method) : typeOperation(call.method);
	if (selected == null)
		return null;
	if (call.arguments.length != selected.arguments.length)
		throw "stage3 emitter: " + call.owner + "." + call.method + " requires " + selected.arguments.length + " argument(s)";
	final arguments = [
		for (index in 0...call.arguments.length)
			argument(input, call.arguments[index], selected.arguments[index])
	];
	if (arguments.length == 1)
		return "(" + selected.reference + " (" + arguments[0] + "))";
	if (input.names == null)
		throw "stage3 emitter: " + call.owner + "." + call.method + " requires its local naming owner";
	return Stage3OcamlCallOrder.render({callee: selected.reference, arguments: arguments, names: input.names});
}

/** Pass one argument unchanged, or as the runtime's `Obj.t` carrier. */
private function argument(input:ReflectCallInput, expression:HxExpr, kind:ReflectArgument):String {
	final rendered = input.emit(expression);
	if (kind == Plain)
		return rendered;
	return Stage3OcamlValueConversion.dynamicValue(input.argumentType(expression), rendered, "stage3 emitter: " + input.call.owner + "." + input.call.method);
}

/**
	`Type.typeof(value)`: classify the value once in the runtime, then build the
	matching constructor of the generated `ValueType` enum. `TClass` and `TEnum`
	receive the runtime class or enum value.
 */
private function valueType(input:ReflectCallInput):String {
	final call = input.call;
	if (call.arguments.length != 1)
		throw "stage3 emitter: Type.typeof requires 1 argument";
	if (input.names == null)
		throw "stage3 emitter: Type.typeof requires its local naming owner";
	final value = input.names.internalName("__hx_typeof_value");
	final cases = new Array<String>();
	for (index in 0...VALUE_TYPE_CONSTRUCTORS.length) {
		final name = VALUE_TYPE_CONSTRUCTORS[index];
		final constructor = input.valueTypeConstructor(name, index);
		final result = switch name {
			case "TClass": constructor + " (HxReflect.value_class " + value + ")";
			case "TEnum": constructor + " (HxType.getEnum " + value + ")";
			case _: constructor;
		};
		cases.push((name == "TUnknown" ? "_" : Std.string(index)) + " -> " + result);
	}
	return "(let " + value + " = " + argument(input, call.arguments[0], Value) + " in match HxReflect.value_type_index " + value + " with "
		+ cases.join(" | ") + ")";
}
