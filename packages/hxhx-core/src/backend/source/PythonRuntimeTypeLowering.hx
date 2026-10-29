package backend.source;

import haxe.ds.StringMap;

/**
	One Python runtime type operation selected from an exact typed occurrence.

	`value` is the already-lowered tested operand. It is null for a class value,
	which evaluates no operand.
**/
typedef PythonRuntimeTypeOperation = {
	final check:PythonRuntimeTypeCheck;
	final value:Null<HxExpr>;
}

/** Closed set of Python representations admitted for runtime type operands. */
enum PythonRuntimeTypeCheck {
	IntValue;
	FloatValue;
	BoolValue;
	StringValue;
	DynamicValue;
	ArrayValue;
	EmittedClass(className:String);
}

/**
	The exact typed facts of one executable projection that a runtime type
	lowering may consult. Function and field-initializer projections both
	provide them, so lookups never cross into another body.
**/
typedef PythonRuntimeTypeFacts = {
	final requireRuntimeType:HxExpr->TypedBackendRuntimeTypeOccurrence;
	final findCast:HxExpr->Null<TypedBackendCastOccurrence>;
}

/**
	Lower runtime type checks and class values for the Python source target.

	Why: shared typing replaces `value is T` with a test marker and every type
	used as a value (such as the `T` in `Std.isOfType(value, T)`) with a value
	marker. Neither marker carries a type name; the executable projection's
	catalog records the selected type. Python must read that exact occurrence
	instead of guessing from source spelling. The Python backend does not emit
	the standard library's `Std` class, so a call to the exact standard
	`Std.isOfType` declaration with a direct type argument becomes the same
	inline test as `is`.

	What: each admitted check renders as:

	| Haxe target | Python test                                                    |
	| ----------- | -------------------------------------------------------------- |
	| `Int`       | `hxhx_is_int_value(v)`: a non-Bool `int`, or an integral `float` in 32-bit range |
	| `Float`     | `hxhx_is_float_value(v)`: a non-Bool `int` or `float`          |
	| `Bool`      | `isinstance(v, bool)`                                          |
	| `String`    | `isinstance(v, str)`                                           |
	| `Dynamic`   | `(v is not None)`                                              |
	| `Array`     | `isinstance(v, list)`                                          |
	| user class  | `isinstance(v, Cls)`; Python inheritance answers subclasses     |

	A `null` operand fails every test, as in Haxe. A bare user class value
	renders as its emitted Python class.

	Fail closed: interfaces, enums, `Class`/`Enum` meta checks, classes this
	backend does not emit as Python classes (standard-library or extern
	declarations, or a short name shared by two emitted classes), core types used
	as runtime values outside a direct `Std.isOfType` argument, and
	`Std.isOfType` with a computed type argument are compiler errors raised
	before any output file is written.
**/
class PythonRuntimeTypeLowering {
	static inline final MARKER = "$hxhx:python-runtime-type";
	static inline final IS_OF_TYPE = "Std#static:isOfType(required:dynamic,required:dynamic)->primitive:Bool#0";

	final classes:StringMap<HxClassDecl>;

	/** @param classes Emitted, unambiguous Python classes keyed by canonical typed identity. */
	public function new(classes:StringMap<HxClassDecl>) {
		this.classes = classes;
	}

	/**
		Rewrite one node of a projected body. `original` is the projected node and
		`rebuilt` the same node with already-lowered children. Returns null when
		the node is not a runtime type operation.

		A class value keeps its check so the enclosing `Std.isOfType` call can
		consume it; rendering rejects a core check that survives as a value.
	**/
	public function rewrite(facts:PythonRuntimeTypeFacts, original:HxExpr, rebuilt:HxExpr):Null<HxExpr> {
		if (TypedRuntimeTypeSource.isMarker(original)) {
			final occurrence = facts.requireRuntimeType(original);
			occurrence.assertCurrent();
			return switch (rebuilt) {
				case ECall(_, []) if (occurrence.getValue() == null): encode(check(occurrence.getTarget()), null);
				case ECall(_, [value]) if (occurrence.getValue() != null): encode(check(occurrence.getTarget()), value);
				case _: throw "Python runtime type marker lost its evaluated value";
			};
		}
		final call = TypedExactStaticCallSource.decode(original);
		if (call == null || call.declaration != IS_OF_TYPE)
			return null;
		final lowered = TypedExactStaticCallSource.decode(rebuilt);
		if (call.arguments.length != 2 || lowered == null || lowered.arguments.length != 2)
			throw "Python Std.isOfType requires its value and type arguments";
		final occurrence = facts.requireRuntimeType(typeArgument(facts, call.arguments[1]));
		if (occurrence.getValue() != null)
			throw "Python Std.isOfType requires a class value as its type argument";
		return encode(check(occurrence.getTarget()), lowered.arguments[0]);
	}

	/** Peel grouping and certified class-value conversions; a computed type argument is rejected. */
	static function typeArgument(facts:PythonRuntimeTypeFacts, expression:HxExpr):HxExpr {
		return switch (expression) {
			case EParenthesized(inner, _): typeArgument(facts, inner);
			case ECast(_, _):
				final conversion = facts.findCast(expression);
				if (conversion == null || !conversion.isRepresentationPreserving())
					throw "Python Std.isOfType requires a certified type-value conversion";
				typeArgument(facts, conversion.getOperand());
			case _ if (TypedRuntimeTypeSource.isMarker(expression)): expression;
			case _: throw "Python source target does not support runtime type operands in Std.isOfType with a computed type argument";
		};
	}

	function check(target:TypedRuntimeTypeTarget):PythonRuntimeTypeCheck {
		return switch (target.getKind()) {
			case IntCore: IntValue;
			case FloatCore: FloatValue;
			case BoolCore: BoolValue;
			case StringCore: StringValue;
			case DynamicCore: DynamicValue;
			case ArrayCore: ArrayValue;
			case Nominal(identity): EmittedClass(emittedClass(target, identity));
			case EnumDeclaration(_) | ClassCore | EnumCore: unsupported(target);
		};
	}

	function emittedClass(target:TypedRuntimeTypeTarget, identity:TyNominalTypeId):String {
		final declaration = classes.get(identity.getCanonicalName());
		if (declaration == null || declaration.isInterface)
			unsupported(target);
		return HxClassDecl.getName(declaration);
	}

	static function unsupported<T>(target:TypedRuntimeTypeTarget):T
		throw "Python source target does not support runtime type operands: " + target.getSemanticKey();

	static function encode(check:PythonRuntimeTypeCheck, value:Null<HxExpr>):HxExpr {
		final payload:Array<HxExpr> = switch (check) {
			case IntValue: [EString("int")];
			case FloatValue: [EString("float")];
			case BoolValue: [EString("bool")];
			case StringValue: [EString("string")];
			case DynamicValue: [EString("dynamic")];
			case ArrayValue: [EString("array")];
			case EmittedClass(name): [EString("class"), EString(name)];
		};
		return ECall(EUnsupported(MARKER), value == null ? payload : payload.concat([value]));
	}

	/** Recognize only nodes produced by `encode`; malformed payloads are compiler errors. */
	public static function decode(expression:HxExpr):Null<PythonRuntimeTypeOperation> {
		final payload = switch (expression) {
			case ECall(EUnsupported(MARKER), payload): payload;
			case _: return null;
		};
		return switch (payload) {
			case [EString("class"), EString(name)]: {check: EmittedClass(name), value: null};
			case [EString("class"), EString(name), value]: {check: EmittedClass(name), value: value};
			case [EString(tag)]: {check: coreCheck(tag), value: null};
			case [EString(tag), value]: {check: coreCheck(tag), value: value};
			case _: throw "Python runtime type operation has malformed target data";
		};
	}

	static function coreCheck(tag:String):PythonRuntimeTypeCheck {
		return switch (tag) {
			case "int": IntValue;
			case "float": FloatValue;
			case "bool": BoolValue;
			case "string": StringValue;
			case "dynamic": DynamicValue;
			case "array": ArrayValue;
			case _: throw "Python runtime type operation has an unknown check: " + tag;
		};
	}

	/**
		Render a decoded operation. `operand` renders the tested value exactly once;
		`className` maps an emitted declaration name to its Python identifier.
	**/
	public static function render(operation:PythonRuntimeTypeOperation, operand:HxExpr->String, className:String->String):String {
		if (operation.value == null)
			return switch (operation.check) {
				case EmittedClass(name): className(name);
				case _: throw "Python source target does not support runtime type operands as core type values outside a direct Std.isOfType argument";
			};
		final value = operand(operation.value);
		return switch (operation.check) {
			case IntValue: "hxhx_is_int_value(" + value + ")";
			case FloatValue: "hxhx_is_float_value(" + value + ")";
			case BoolValue: "isinstance(" + value + ", bool)";
			case StringValue: "isinstance(" + value + ", str)";
			case DynamicValue: "(" + value + " is not None)";
			case ArrayValue: "isinstance(" + value + ", list)";
			case EmittedClass(name): "isinstance(" + value + ", " + className(name) + ")";
		};
	}
}
