package backend.ocaml;

import backend.ocaml.Stage3OcamlEnumPlan.Stage3OcamlEnumConstructor;
import backend.ocaml.Stage3OcamlEnumPlan.Stage3OcamlEnumPayload;
import TypedExactEnumConstructorSource.TypedExactEnumConstructorCall;

/**
	Emits ordinary enum values using the variants understood by HxEnum and HxType.

	Each compiler request supplies its exact typed declarations. Constructor calls
	select those declarations by identity; source qualifiers do not select runtime
	owners. Haxe constructor indexes retain declaration order, while OCaml numbers
	singletons and payload constructors separately.

	The native payload contract covers Int, Bool, String, Dynamic, anonymous records,
	typed arrays, runtime type values, and boxed ordinary enums,
	including their optional and nullable forms. Other payload representations fail
	explicitly until their typed conversion is implemented. A function payload
	(`Unrepresentable`) fails where it is used: a constructor call, or a pattern that
	binds or tests that payload. Declaring the enum, or matching the constructor with
	`_` in that position, still builds.
**/
class Stage3OcamlEnums {
	final owners:Map<String, Stage3OcamlEnumPlan> = new Map();
	final byDeclaration:Map<HxClassDecl, Stage3OcamlEnumPlan> = new Map();
	final valueName:String->String;
	final quote:String->String;
	var nextCall:Int = 0;

	public function new(valueName:String->String, quote:String->String) {
		this.valueName = valueName;
		this.quote = quote;
	}

	/** Register only declarations whose parser and semantic enum identities agree. */
	public function add(projection:TypedBackendClassProjection, outputModule:String, packagePath:String):Void {
		final plan = Stage3OcamlEnumPlan.fromProjection(projection, outputModule, packagePath, valueName);
		if (plan == null)
			return;
		if (owners.exists(plan.owner))
			throw "OCaml enum owner registered twice: " + plan.owner;
		for (other in owners)
			if (other.runtimeName == plan.runtimeName || other.outputModule == plan.outputModule)
				throw "OCaml enum runtime or module name collision: " + plan.owner;
		owners.set(plan.owner, plan);
		byDeclaration.set(projection.getDeclaration(), plan);
	}

	/** Validate after all owners are registered so recursive enum payloads resolve exactly. */
	public function validate():Void {
		for (owner in owners)
			for (constructor in owner.constructors)
				payloadTypes(constructor);
	}

	/** Exception boundaries may retain only enum boxes registered by this request. */
	public function runtimeName(type:TyType):Null<String> {
		final plain = type.unwrapNull();
		final identity = plain.getNominalIdentity();
		if (identity == null || plain.getTypeArguments().length != 0)
			return null;
		final owner = owners.get(identity.getCanonicalName());
		return owner == null ? null : owner.runtimeName;
	}

	/**
		The OCaml value of one constructor of an enum emitted by this request:
		the singleton value, or the function that builds a payload constructor.
		The constructor must be at its declared Haxe index, so a runtime that
		classifies values by index builds the constructor it means.
	 */
	public function constructorValue(owner:String, constructor:String, index:Int, currentModule:String):String {
		final plan = owners.get(owner);
		if (plan == null)
			throw "OCaml enum constructor requires its emitted enum: " + owner;
		for (candidate in plan.constructors)
			if (candidate.name == constructor) {
				if (candidate.index != index)
					throw "OCaml enum constructor " + owner + "." + constructor + " is not at index " + index;
				return (plan.outputModule == currentModule ? "" : plan.outputModule + ".") + candidate.targetName;
			}
		throw "OCaml enum " + owner + " has no constructor " + constructor;
	}

	/** Match only the enum and constructor admitted from the selected typed declaration. */
	public function patternCondition(selected:TypedNamedPattern, value:String):String {
		return switch selected.getKind() {
			case Constructor(identity, name, index, arity):
				final owner = owners.get(identity.getCanonicalName());
				if (owner == null || index < 0 || index >= owner.constructors.length)
					throw "OCaml guarded pattern has no exact enum provider";
				final constructor = owner.constructors[index];
				if (constructor.name != name || constructor.index != index || constructor.payloads.length != arity)
					throw "OCaml guarded constructor differs from typing";
				"(HxEnum.name_opt (Obj.repr "
				+ value
				+ ") = Some "
				+ quote(owner.runtimeName)
				+ " && HxType.enumIndex (Obj.repr "
				+ value
				+ ") = "
				+ index
				+ ")";
			case _: throw "OCaml guarded constructor test requires an ordinary enum";
		};
	}

	static function isBoolPayload(payload:Stage3OcamlEnumPayload):Bool {
		return switch payload {
			case NativeBool: true;
			case NullableValue(value): isBoolPayload(value);
			case _: false;
		};
	}

	/** Reject erased or unmodeled payloads instead of claiming a native variant exists. */
	function payloadTypes(constructor:Stage3OcamlEnumConstructor):Array<String> {
		return [
			for (payload in constructor.payloads)
				payloadType(payload.storage, constructor.declaration)
		];
	}

	/** A nullable payload must still prove that its non-null representation is supported. */
	function payloadType(payload:Stage3OcamlEnumPayload, declaration:String):String {
		return switch (payload) {
			case NativeInt: "int";
			case NativeBool: "bool";
			case NativeString: "string";
			case DynamicValue: "Obj.t";
			case RuntimeTypeValue: "Obj.t";
			case AnonymousRecord(_): "Obj.t";
			case ArrayValue(_): "Obj.t";
			case EnumBox(identity):
				if (!owners.exists(identity))
					throw "OCaml enum payload representation is not implemented: " + declaration + " / " + identity;
				"Obj.t";
			case NullableValue(value):
				payloadType(value, declaration);
				"Obj.t";
			// The slot keeps the variant's shape; no emitted code builds or reads it.
			case Unrepresentable(_): "Obj.t";
		};
	}

	/**
		Why an open record cannot enter a record payload as `destination`, or null when it can.

		Upstream binds a record literal's open parts (`[]`, an unresolved value) when the
		constructor call unifies them (`FFun(func)` in `tests/unit/src/unit/UnitBuilder.hx`). hxhx's
		typer proves the record compatible but keeps those parts unknown. The record carrier stores
		each field value as the literal built it. That is the destination's own storage only where
		the destination stores a reference: an Array, structure, class instance, enum, String, or a
		nullable reference. An open part anywhere else (Int, Float, Bool, Dynamic, a function) is
		rejected and named.
	**/
	function openRecordFailure(source:TyType, destination:TyType, path:String, classIdentity:Null<TyType->Bool>):Null<String> {
		if (!destination.isAnonymous())
			return openFieldMessage(path, destination);
		final targets = destination.getAnonymousFields();
		for (field in source.getAnonymousFields()) {
			if (!field.type.hasUnknownComponent())
				continue;
			var target:Null<TyType> = null;
			for (candidate in targets)
				if (candidate.name == field.name)
					target = candidate.type;
			final name = path + field.name;
			if (target == null)
				return "OCaml record enum argument has open field `" + name + "` with no destination field";
			final failure = openValueFailure(field.type, target, name, classIdentity);
			if (failure != null)
				return failure;
		}
		return null;
	}

	function openValueFailure(source:TyType, destination:TyType, path:String, classIdentity:Null<TyType->Bool>):Null<String> {
		final target = TyAliasExpansion.reveal(destination);
		if (source.isUnknown() || (source.isNullable() && source.unwrapNull().isUnknown()))
			return storesReference(target, classIdentity) ? null : openFieldMessage(path, target);
		if (source.isNullable())
			return openValueFailure(source.unwrapNull(), target.unwrapNull(), path, classIdentity);
		if (source.isAnonymous())
			return openRecordFailure(source, target, path + ".", classIdentity);
		final sourceIdentity = source.getNominalIdentity();
		final targetIdentity = target.getNominalIdentity();
		if (sourceIdentity != null
			&& sourceIdentity.getCanonicalName() == "Array"
			&& targetIdentity != null
			&& targetIdentity.getCanonicalName() == "Array"
			&& source.getTypeArguments().length == 1
			&& target.getTypeArguments().length == 1) {
			// `[]`: the field stores the Array object itself, and the literal has no element yet.
			final element = source.getTypeArguments()[0];
			return element.isUnknown() ? null : openValueFailure(element, target.getTypeArguments()[0], path + "[]", classIdentity);
		}
		return openFieldMessage(path, target);
	}

	/** Whether a value of `type` keeps its own `Obj.t` in a record field. */
	function storesReference(type:TyType, classIdentity:Null<TyType->Bool>):Bool {
		if (type.hasUnknownComponent() || type.isDynamic() || type.isFunction())
			return false;
		if (type.isNullable()) {
			final inner = TyAliasExpansion.reveal(type.unwrapNull());
			// Null<Int>, Null<Float>, and Null<Bool> use their own nullable carriers.
			return inner.isPrimitive() ? inner.getDisplay() == "String" : storesReference(inner, classIdentity);
		}
		if (type.isPrimitive())
			return type.getDisplay() == "String";
		if (type.isAnonymous())
			return true;
		final identity = type.getNominalIdentity();
		if (identity == null)
			return false;
		if (identity.getCanonicalName() == "Array" || owners.exists(identity.getCanonicalName()))
			return true;
		return classIdentity != null && classIdentity(type);
	}

	static function openFieldMessage(path:String, destination:TyType):String
		return "OCaml record enum argument cannot store open field `"
			+ path
			+ "` as "
			+ destination.getDisplay()
			+ ": an open part needs a reference destination (Array, structure, class, enum, String, or a nullable reference)";

	/**
		A constructor pattern may name an unrepresentable payload only with `_`: binding or
		testing it needs a value no emitted code can build. `arguments` are the pattern's own
		payload patterns, in declaration order.
	**/
	public function requireBindable(selected:TypedNamedPattern, arguments:Array<HxSwitchPattern>):Void {
		switch selected.getKind() {
			case Constructor(identity, _, index, _):
				final owner = owners.get(identity.getCanonicalName());
				if (owner == null || index < 0 || index >= owner.constructors.length)
					return;
				final payloads = owner.constructors[index].payloads;
				for (position in 0...arguments.length) {
					if (position >= payloads.length)
						break;
					final failure = Stage3OcamlEnumPlan.unrepresentable(payloads[position].storage);
					if (failure != null && !arguments[position].match(PWildcard))
						throw failure;
				}
			case _:
		}
	}

	/** Produce one enum module; ordinary classes continue through their own emitter. */
	public function render(projection:TypedBackendClassProjection):Null<String> {
		if (HxClassDecl.getEnumDeclaration(projection.getDeclaration()) == null)
			return null;
		final owner = byDeclaration.get(projection.getDeclaration());
		if (owner == null)
			throw "OCaml enum module is missing its request-owned declaration";
		final out = ["(* Generated from the exact typed enum declaration. *)", "type t ="];
		if (owner.constructors.length == 0)
			out.push("  |");
		for (constructor in owner.constructors) {
			final types = payloadTypes(constructor);
			out.push("  | Constructor_" + constructor.index + (types.length == 0 ? "" : " of " + types.join(" * ")));
		}
		var immediateTag = 0;
		var blockTag = 0;
		for (constructor in owner.constructors) {
			final types = payloadTypes(constructor);
			final args = [for (index in 0...types.length) "arg" + index];
			final parameters = [for (index in 0...types.length) "(" + args[index] + " : " + types[index] + ")"];
			final payload = args.copy();
			// Keep each payload construction fresh, including all-constant arguments.
			if (payload.length > 0)
				payload[0] = "Stdlib.Sys.opaque_identity " + payload[0];
			final variant = "Constructor_" + constructor.index + (payload.length == 0 ? "" : " (" + payload.join(", ") + ")");
			out.push("let " + constructor.targetName + " " + parameters.join(" ") + " : Obj.t = HxEnum.box_if_needed " + quote(owner.runtimeName)
				+ " (Obj.repr (" + variant + "))");
			final layout = types.length == 0 ? "HxType.EnumImmediate " + immediateTag++ : "HxType.EnumBlock " + blockTag++;
			out.push("let () = HxType.register_enum_ctor_layout " + quote(owner.runtimeName) + " " + quote(constructor.name) + " " + constructor.index
				+ " (" + layout + ")");
			// A Bool payload is a raw OCaml bool; tell enum text which positions hold one.
			final bools = [
				for (index in 0...constructor.payloads.length)
					if (isBoolPayload(constructor.payloads[index].storage)) Std.string(index)
			];
			if (bools.length > 0)
				out.push("let () = HxDynamic.register_enum_bool_arguments " + quote(owner.runtimeName) + " " + quote(constructor.name) + " ["
					+ bools.join("; ") + "]");
		}
		out.push("let () = ignore (HxType.enum_ " + quote(owner.runtimeName) + ")");
		return out.join("\n") + "\n";
	}

	/**
		Validate the selected constructor, then evaluate its arguments once in Haxe
		order. Native variants need every payload slot, so omitted optional arguments
		receive null. Nested lets preserve Haxe's argument evaluation order.
		The active executable supplies each Dynamic operand's retained source type
		and each record or array operand's source and expected destination. The exact
		constructor plan owns the destination and selects the conversion.
	**/
	public function call(selected:TypedExactEnumConstructorCall, emit:HxExpr->String, names:Stage3OcamlLocalNames,
			argumentFacts:HxExpr->Null<TypedBackendCallArgument>, ?classIdentity:TyType->Bool):String {
		final owner = owners.get(selected.owner);
		if (owner == null || owner.moduleIdentity != selected.modulePath)
			throw "OCaml enum call has no exact program owner: " + selected.owner;
		for (constructor in owner.constructors) {
			if (constructor.name != selected.constructor)
				continue;
			if (constructor.payloads.length == 0)
				throw "OCaml enum call selected a singleton field";
			if (constructor.declaration != selected.declaration || selected.arguments.length > constructor.payloads.length)
				throw "OCaml enum call disagrees with its exact constructor declaration";
			for (payload in constructor.payloads) {
				final failure = Stage3OcamlEnumPlan.unrepresentable(payload.storage);
				if (failure != null)
					throw failure;
			}
			final operands = selected.arguments.copy();
			while (operands.length < constructor.payloads.length) {
				if (!constructor.payloads[operands.length].optional)
					throw "OCaml enum call disagrees with its exact constructor declaration";
				operands.push(ENull);
			}
			final callId = nextCall++;
			final args = [
				for (index in 0...operands.length)
					names.internalName("__hx_enum_arg_" + callId + "_" + index)
			];
			final bindings = [
				for (index in 0...args.length) {
					final rendered = emit(operands[index]);
					final stored = switch (constructor.payloads[index].storage) {
						case ArrayValue(storageType), NullableValue(ArrayValue(storageType)):
							if (index >= selected.arguments.length || operands[index].match(ENull)) {
								"Obj.repr (" + rendered + ")";
							} else {
								final fact = argumentFacts(operands[index]);
								if (fact == null
									|| fact.expression != operands[index]
									|| fact.expectedType == null
									|| !TyAliasEquivalence.equivalentTypes(TyAliasExpansion.revealNonNullable(fact.expectedType), storageType)
									|| !TyAliasEquivalence.equivalentTypes(TyAliasExpansion.revealNonNullable(fact.type), storageType)
									|| fact.type.hasUnknownComponent())
									throw "OCaml array enum argument requires its exact typed array operand and destination";
								// Box the existing array object, not its elements. Matching the
								// complete storage type preserves their selected representation;
								// transparent aliases do not add a conversion or copy.
								"Obj.repr (" + rendered + ")";
							}
						case AnonymousRecord(key), NullableValue(AnonymousRecord(key)):
							if (index >= selected.arguments.length || operands[index].match(ENull)) {
								"Obj.repr (" + rendered + ")";
							} else {
								final fact = argumentFacts(operands[index]);
								if (fact == null
									|| fact.expression != operands[index]
									|| fact.expectedType == null
									|| TyAliasExpansion.revealNonNullable(fact.expectedType).getSemanticKey() != key
									|| !TyAliasExpansion.revealNonNullable(fact.type).isAnonymous())
									throw "OCaml record enum argument requires its exact typed record operand and destination";
								// An open literal (`{args: [], ret: null}`) keeps its parts as stored; see openRecordFailure.
								if (fact.type.hasUnknownComponent()) {
									final failure = openRecordFailure(TyAliasExpansion.revealNonNullable(fact.type),
										TyAliasExpansion.revealNonNullable(fact.expectedType), "", classIdentity);
									if (failure != null)
										throw failure;
								}
								// The typed object owner already stores fields, including Bool,
								// inside this carrier. Preserve the object instead of rebuilding it.
								rendered;
							}
						case DynamicValue, NullableValue(DynamicValue):
							// Literal or omitted null has one runtime carrier. Other values
							// need their source type so Bool cannot become integer 0 or 1.
							if (index >= selected.arguments.length || operands[index].match(ENull)) {
								"Obj.repr (" + rendered + ")";
							} else {
								final fact = argumentFacts(operands[index]);
								if (fact == null || fact.expression != operands[index] || fact.type.hasUnknownComponent())
									throw "OCaml Dynamic enum argument requires its exact typed operand";
								// The selected constructor owns the destination. The operand
								// record supplies only its source carrier for this conversion.
								final carrier = fact.type.getSemanticKey() == "primitive:Bool" ? OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.ExactBool : fact.type.isDynamic() ? OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.DynamicValue : OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.ConcreteValue;
								OcamlDynamicOperatorLowering.callArgument("Dynamic", carrier, rendered);
							}
						// Obj.repr preserves the null sentinel and already-boxed values.
						// It also gives a concrete primitive the declared Obj.t storage type.
						case NullableValue(_): "Obj.repr (" + rendered + ")";
						case _: rendered;
					};
					"let " + args[index] + " = (" + stored + ") in ";
				}
			];
			return "(" + bindings.join("") + owner.outputModule + "." + constructor.targetName + " " + args.join(" ") + ")";
		}
		throw "OCaml enum call selected an absent constructor: " + selected.constructor;
	}
}
