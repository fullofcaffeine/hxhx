package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
#if macro
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
#end

/** The standard Haxe Map carrier selected from a statically known `IMap` key. */
enum abstract OcamlStandardIMapKeyKind(String) from String to String {
	final StringKey = "string";
	final IntKey = "int";
	final ObjectIdentityKey = "object-identity";
}

/** One Haxe 4.3.7 `haxe.Constraints.IMap` operation admitted before syntax. */
enum abstract OcamlStandardIMapOperation(String) from String to String {
	final Set = "set";
	final Get = "get";
	final Exists = "exists";
	final Remove = "remove";
	final Keys = "keys";
	final Values = "iterator";
	final Pairs = "key-value-iterator";
	final Copy = "copy";
	final ToString = "to-string";
	final Clear = "clear";
}

/** How syntax mechanically adapts the already selected runtime operation. */
enum abstract OcamlStandardIMapResultForm(String) from String to String {
	final Direct = "direct";
	final IteratorFromArray = "iterator-from-array";
	final FormattedEntries = "formatted-entries";
}

/** The exact Haxe value-to-text family selected for one formatted Map entry. */
enum abstract OcamlStandardIMapStringifier(String) from String to String {
	final ExactString = "exact-string";
	final ExactInt = "exact-int";
	final ExactFloat = "exact-float";
	final ExactBool = "exact-bool";
	final DynamicObject = "dynamic-object";
}

/**
	The complete target operation for one standard `IMap` call occurrence.

	The plan stores the source receiver and argument types for validation, the
	selected standard Map carrier, the exact runtime symbol, any result adapter,
	and the runtime capabilities packaging must explain. `OcamlBuilder` may
	render these facts but must not rediscover the key kind or source method.
**/
typedef OcamlStandardIMapCallTarget = {
	final operation:OcamlStandardIMapOperation;
	final keyKind:OcamlStandardIMapKeyKind;
	final receiverSemanticTypeId:String;
	final receiverCarrierId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final argumentSemanticTypeIds:Array<String>;
	final resultSemanticTypeId:String;
	final runtimeModule:String;
	final runtimeFunction:String;
	final resultForm:OcamlStandardIMapResultForm;
	final iteratorModule:Null<String>;
	final iteratorFunction:Null<String>;
	final keyStringifier:Null<OcamlStandardIMapStringifier>;
	final valueStringifier:Null<OcamlStandardIMapStringifier>;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
}

/**
	Selects and validates standard `IMap` calls from the final typed Haxe body.

	This contract deliberately admits only the three carriers already owned by
	the OCaml target: String keys, Int keys, and non-generic class keys compared
	by object identity. Enum maps, type-parameter keys, structural keys, and
	user-defined `IMap` implementations are not supported by this boundary. The
	typed `IMap` declaration proves the method and key family, but it does not
	prove the receiver's runtime implementation; this target therefore makes a
	deliberately narrower claim for values originating from Haxe's standard Map
	specializations.
**/
class OcamlStandardIMapCallContract {
	public static inline final PROOF_ID = "standard-imap-typed-target-call-v1";
	public static inline final MAP_RUNTIME_CAPABILITY = "haxe-map";
	public static inline final ITERATOR_RUNTIME_CAPABILITY = "haxe-iterator";
	public static inline final ARRAY_RUNTIME_CAPABILITY = "haxe-array";
	public static inline final STRING_TEXT_RUNTIME_CAPABILITY = "haxe-string-text";
	public static inline final DYNAMIC_TEXT_RUNTIME_CAPABILITY = "haxe-dynamic-text";

	#if macro
	/** Returns whether this is the exact upstream `haxe.Constraints.IMap`. */
	public static function isIMapClass(classType:ClassType):Bool {
		return classType.pack != null
			&& classType.pack.length == 1
			&& classType.pack[0] == "haxe"
			&& classType.module == "haxe.Constraints"
			&& classType.name == "IMap";
	}

	/** Selects the admitted target carrier for one exact key type. */
	public static function keyKindForType(type:Type):Null<OcamlStandardIMapKeyKind> {
		if (OcamlRepresentationRegistry.isExactString(type))
			return OcamlStandardIMapKeyKind.StringKey;
		if (OcamlRepresentationRegistry.isExactInt(type))
			return OcamlStandardIMapKeyKind.IntKey;
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, parameters):
				final classType = classRef.get();
				switch [classType.kind, classType.params.length, parameters.length] {
					case [KTypeParameter(_), _, _]:
						null;
					case [_, 0, 0]:
						OcamlStandardIMapKeyKind.ObjectIdentityKey;
					case _:
						null;
				}
			case _:
				null;
		}
	}
	#end

	/** Returns the runtime carrier constructor selected by one admitted key. */
	public static function carrierId(keyKind:OcamlStandardIMapKeyKind):String {
		return switch (keyKind) {
			case StringKey: "HxMap.string_map";
			case IntKey: "HxMap.int_map";
			case ObjectIdentityKey: "HxMap.obj_map";
			case _: throw 'reflaxe.ocaml [ocaml-imap:invalid-key-kind]: unsupported standard IMap key kind "$keyKind"';
		}
	}

	#if macro
	/**
		Plans one typed call in the currently admitted standard-Map subset.

		This identifies the source declaration and fixed key family. It does not
		claim that arbitrary user implementations of `IMap` share the `HxMap`
		carrier; those need a separate typed interface-conversion contract.
	**/
	public static function select(classType:ClassType, parameters:Array<Type>, field:ClassField, receiver:TypedExpr, arguments:Array<TypedExpr>,
			resultType:Type):Null<OcamlStandardIMapCallTarget> {
		if (!isIMapClass(classType) || parameters.length != 2)
			return null;
		final keyKind = keyKindForType(parameters[0]);
		if (keyKind == null)
			return null;
		final operation = operationFor(field.name, arguments.length);
		if (operation == null)
			return null;
		final keySemanticTypeId = semanticTypeId(parameters[0]);
		final valueSemanticTypeId = semanticTypeId(parameters[1]);
		final receiverSemanticTypeId = semanticTypeId(receiver.t);
		final resultSemanticTypeId = semanticTypeId(resultType);
		if (resultSemanticTypeId != expectedResultSemanticTypeId(operation, receiverSemanticTypeId, keySemanticTypeId, valueSemanticTypeId))
			return null;
		final resultForm = resultFormFor(operation);
		final iterator = resultForm == OcamlStandardIMapResultForm.IteratorFromArray
			|| resultForm == OcamlStandardIMapResultForm.FormattedEntries;
		final formatted = resultForm == OcamlStandardIMapResultForm.FormattedEntries;
		final keyStringifier = formatted ? stringifierFor(parameters[0]) : null;
		final valueStringifier = formatted ? stringifierFor(parameters[1]) : null;
		final runtimeCapabilities = runtimeCapabilities(iterator, formatted, keyStringifier, valueStringifier);
		final target:OcamlStandardIMapCallTarget = {
			operation: operation,
			keyKind: keyKind,
			receiverSemanticTypeId: receiverSemanticTypeId,
			receiverCarrierId: carrierId(keyKind),
			keySemanticTypeId: keySemanticTypeId,
			valueSemanticTypeId: valueSemanticTypeId,
			argumentSemanticTypeIds: arguments.map(argument -> semanticTypeId(argument.t)),
			resultSemanticTypeId: resultSemanticTypeId,
			runtimeModule: "HxMap",
			runtimeFunction: runtimeFunction(operation, keyKind),
			resultForm: resultForm,
			iteratorModule: iterator ? "HxIterator" : null,
			iteratorFunction: iterator ? "of_array" : null,
			keyStringifier: keyStringifier,
			valueStringifier: valueStringifier,
			runtimeCapabilities: runtimeCapabilities,
			proofId: PROOF_ID,
			proofClaim: "The final typed Haxe call resolves to the standard haxe.Constraints.IMap declaration with a fixed String, Int, or non-generic class key in the OCaml target's currently admitted standard-Map receiver subset. That key selects exactly one existing HxMap carrier and operation before OCaml syntax; iterator and text adapters are also explicit. This proof does not admit arbitrary user-defined IMap implementations, which require a separate typed interface-conversion and dispatch contract."
		};
		require(target);
		return target;
	}

	/** Rechecks a sealed target against the typed occurrence that consumes it. */
	public static function matches(target:OcamlStandardIMapCallTarget, classType:ClassType, parameters:Array<Type>, field:ClassField, receiver:TypedExpr,
			arguments:Array<TypedExpr>, resultType:Type):Bool {
		final selected = select(classType, parameters, field, receiver, arguments, resultType);
		return selected != null && fingerprint(selected) == fingerprint(target);
	}
	#end

	/** Rejects incomplete or internally conflicting standard Map operations. */
	public static function require(target:OcamlStandardIMapCallTarget):Void {
		if (target == null)
			throw "reflaxe.ocaml [ocaml-imap:invalid-plan]: standard IMap target must not be null";
		if (target.proofId != PROOF_ID || target.proofClaim.length == 0)
			throw "reflaxe.ocaml [ocaml-imap:invalid-plan]: standard IMap target has no matching typed-call proof";
		final expectedArguments = argumentSemanticTypeIds(target.operation, target.keySemanticTypeId, target.valueSemanticTypeId);
		final expectedResult = expectedResultSemanticTypeId(target.operation, target.receiverSemanticTypeId, target.keySemanticTypeId,
			target.valueSemanticTypeId);
		if (target.receiverSemanticTypeId.length == 0
			|| target.keySemanticTypeId.length == 0
			|| target.valueSemanticTypeId.length == 0
			|| target.resultSemanticTypeId.length == 0
			|| target.receiverSemanticTypeId != 'haxe.IMap<${target.keySemanticTypeId}, ${target.valueSemanticTypeId}>'
			|| !keyKindMatchesSemanticType(target.keyKind, target.keySemanticTypeId)
			|| target.receiverCarrierId != carrierId(target.keyKind)
			|| target.runtimeModule != "HxMap"
			|| target.runtimeFunction != runtimeFunction(target.operation, target.keyKind)
			|| target.argumentSemanticTypeIds.join(",") != expectedArguments.join(",")
			|| target.resultSemanticTypeId != expectedResult
			|| target.resultForm != resultFormFor(target.operation)) {
			throw "reflaxe.ocaml [ocaml-imap:invalid-plan]: standard IMap target disagrees with its selected carrier, method, or typed signature";
		}
		final iterator = target.resultForm == OcamlStandardIMapResultForm.IteratorFromArray
			|| target.resultForm == OcamlStandardIMapResultForm.FormattedEntries;
		if (iterator != (target.iteratorModule == "HxIterator" && target.iteratorFunction == "of_array"))
			throw "reflaxe.ocaml [ocaml-imap:invalid-plan]: standard IMap target has an invalid iterator adapter";
		final formatted = target.resultForm == OcamlStandardIMapResultForm.FormattedEntries;
		if (formatted != (target.keyStringifier != null && target.valueStringifier != null))
			throw "reflaxe.ocaml [ocaml-imap:invalid-plan]: standard IMap target has an invalid text-formatting contract";
		if (formatted
			&& (target.keyStringifier != stringifierForSemanticTypeId(target.keySemanticTypeId)
				|| target.valueStringifier != stringifierForSemanticTypeId(target.valueSemanticTypeId))) {
			throw "reflaxe.ocaml [ocaml-imap:invalid-plan]: standard IMap target has stringifiers that disagree with its typed key or value";
		}
		final expectedCapabilities = runtimeCapabilities(iterator, formatted, target.keyStringifier, target.valueStringifier);
		if (target.runtimeCapabilities.join(",") != expectedCapabilities.join(","))
			throw "reflaxe.ocaml [ocaml-imap:invalid-plan]: standard IMap target has an invalid runtime-capability inventory";
	}

	/** Copies one target so a request cannot mutate the sealed plan in place. */
	public static function copy(target:OcamlStandardIMapCallTarget):OcamlStandardIMapCallTarget {
		return {
			operation: target.operation,
			keyKind: target.keyKind,
			receiverSemanticTypeId: target.receiverSemanticTypeId,
			receiverCarrierId: target.receiverCarrierId,
			keySemanticTypeId: target.keySemanticTypeId,
			valueSemanticTypeId: target.valueSemanticTypeId,
			argumentSemanticTypeIds: target.argumentSemanticTypeIds.copy(),
			resultSemanticTypeId: target.resultSemanticTypeId,
			runtimeModule: target.runtimeModule,
			runtimeFunction: target.runtimeFunction,
			resultForm: target.resultForm,
			iteratorModule: target.iteratorModule,
			iteratorFunction: target.iteratorFunction,
			keyStringifier: target.keyStringifier,
			valueStringifier: target.valueStringifier,
			runtimeCapabilities: target.runtimeCapabilities.copy(),
			proofId: target.proofId,
			proofClaim: target.proofClaim
		};
	}

	/** Canonical form used by call identities and deterministic reports. */
	public static function fingerprint(target:OcamlStandardIMapCallTarget):String {
		require(target);
		return [
			(target.operation : String),
			(target.keyKind : String),
			target.receiverSemanticTypeId,
			target.receiverCarrierId,
			target.keySemanticTypeId,
			target.valueSemanticTypeId,
			target.argumentSemanticTypeIds.join(","),
			target.resultSemanticTypeId,
			target.runtimeModule + "." + target.runtimeFunction,
			(target.resultForm : String),
			target.iteratorModule ?? "",
			target.iteratorFunction ?? "",
			target.keyStringifier == null ? "" : (target.keyStringifier : String),
			target.valueStringifier == null ? "" : (target.valueStringifier : String),
			target.runtimeCapabilities.join(","),
			target.proofId,
			target.proofClaim
		].join("|");
	}

	/** Stable requirement identities owned by one exact call occurrence. */
	public static function runtimeRequirementIds(callId:String, target:OcamlStandardIMapCallTarget):Array<String> {
		require(target);
		return target.runtimeCapabilities.map(capability -> callId + ":runtime:" + capability);
	}

	/** Returns the exact source-interface field represented by one operation. */
	public static function sourceFieldName(operation:OcamlStandardIMapOperation):String {
		return switch (operation) {
			case Set, Get, Exists, Remove, Keys, Copy, Clear: (operation : String);
			case Values: "iterator";
			case Pairs: "keyValueIterator";
			case ToString: "toString";
			case _: throw 'reflaxe.ocaml [ocaml-imap:invalid-operation]: unsupported standard IMap operation "$operation"';
		}
	}

	#if macro
	static function semanticTypeId(type:Type):String {
		return TypeTools.toString(type);
	}

	static function operationFor(fieldName:String, suppliedArguments:Int):Null<OcamlStandardIMapOperation> {
		return switch (fieldName) {
			case "set" if (suppliedArguments == 2): OcamlStandardIMapOperation.Set;
			case "get" if (suppliedArguments == 1): OcamlStandardIMapOperation.Get;
			case "exists" if (suppliedArguments == 1): OcamlStandardIMapOperation.Exists;
			case "remove" if (suppliedArguments == 1): OcamlStandardIMapOperation.Remove;
			case "keys" if (suppliedArguments == 0): OcamlStandardIMapOperation.Keys;
			case "iterator" if (suppliedArguments == 0): OcamlStandardIMapOperation.Values;
			case "keyValueIterator" if (suppliedArguments == 0): OcamlStandardIMapOperation.Pairs;
			case "copy" if (suppliedArguments == 0): OcamlStandardIMapOperation.Copy;
			case "toString" if (suppliedArguments == 0): OcamlStandardIMapOperation.ToString;
			case "clear" if (suppliedArguments == 0): OcamlStandardIMapOperation.Clear;
			case _:
				null;
		}
	}
	#end

	static function argumentSemanticTypeIds(operation:OcamlStandardIMapOperation, keySemanticTypeId:String, valueSemanticTypeId:String):Array<String> {
		return switch (operation) {
			case Set: [keySemanticTypeId, valueSemanticTypeId];
			case Get, Exists, Remove: [keySemanticTypeId];
			case Keys, Values, Pairs, Copy, ToString, Clear: [];
			case _: throw 'reflaxe.ocaml [ocaml-imap:invalid-operation]: unsupported standard IMap operation "$operation"';
		}
	}

	static function keyKindMatchesSemanticType(keyKind:OcamlStandardIMapKeyKind, semanticTypeId:String):Bool {
		return switch (keyKind) {
			case StringKey: semanticTypeId == "String";
			case IntKey: semanticTypeId == "Int";
			case ObjectIdentityKey:
				semanticTypeId.length > 0
				&& semanticTypeId != "String"
				&& semanticTypeId != "Int"
				&& semanticTypeId.indexOf("<") < 0
				&& semanticTypeId.indexOf("{") < 0
				&& semanticTypeId.indexOf("->") < 0;
			case _: false;
		}
	}

	static function expectedResultSemanticTypeId(operation:OcamlStandardIMapOperation, receiverSemanticTypeId:String, keySemanticTypeId:String,
			valueSemanticTypeId:String):String {
		return switch (operation) {
			case Set, Clear: "Void";
			case Get: 'Null<$valueSemanticTypeId>';
			case Exists, Remove: "Bool";
			case Keys: 'Iterator<$keySemanticTypeId>';
			case Values: 'Iterator<$valueSemanticTypeId>';
			case Pairs: 'KeyValueIterator<$keySemanticTypeId, $valueSemanticTypeId>';
			case Copy: receiverSemanticTypeId;
			case ToString: "String";
			case _: throw 'reflaxe.ocaml [ocaml-imap:invalid-operation]: unsupported standard IMap operation "$operation"';
		}
	}

	static function resultFormFor(operation:OcamlStandardIMapOperation):OcamlStandardIMapResultForm {
		return switch (operation) {
			case Keys, Values, Pairs: OcamlStandardIMapResultForm.IteratorFromArray;
			case ToString: OcamlStandardIMapResultForm.FormattedEntries;
			case Set, Get, Exists, Remove, Copy, Clear: OcamlStandardIMapResultForm.Direct;
			case _: throw 'reflaxe.ocaml [ocaml-imap:invalid-operation]: unsupported standard IMap operation "$operation"';
		}
	}

	static function runtimeFunction(operation:OcamlStandardIMapOperation, keyKind:OcamlStandardIMapKeyKind):String {
		final stem = switch (operation) {
			case Set: "set";
			case Get: "get";
			case Exists: "exists";
			case Remove: "remove";
			case Keys: "keys";
			case Values: "values";
			case Pairs, ToString: "pairs";
			case Copy: "copy";
			case Clear: "clear";
			case _: throw 'reflaxe.ocaml [ocaml-imap:invalid-operation]: unsupported standard IMap operation "$operation"';
		}
		final suffix = switch (keyKind) {
			case StringKey: "string";
			case IntKey: "int";
			case ObjectIdentityKey: "object";
			case _: throw 'reflaxe.ocaml [ocaml-imap:invalid-key-kind]: unsupported standard IMap key kind "$keyKind"';
		}
		return stem + "_" + suffix;
	}

	#if macro
	static function stringifierFor(type:Type):OcamlStandardIMapStringifier {
		if (OcamlRepresentationRegistry.isExactString(type))
			return OcamlStandardIMapStringifier.ExactString;
		if (OcamlRepresentationRegistry.isExactInt(type))
			return OcamlStandardIMapStringifier.ExactInt;
		if (OcamlRepresentationRegistry.isExactFloat(type))
			return OcamlStandardIMapStringifier.ExactFloat;
		if (OcamlRepresentationRegistry.isExactBool(type))
			return OcamlStandardIMapStringifier.ExactBool;
		return OcamlStandardIMapStringifier.DynamicObject;
	}
	#end

	static function stringifierForSemanticTypeId(semanticTypeId:String):OcamlStandardIMapStringifier {
		return switch (semanticTypeId) {
			case "String": OcamlStandardIMapStringifier.ExactString;
			case "Int": OcamlStandardIMapStringifier.ExactInt;
			case "Float": OcamlStandardIMapStringifier.ExactFloat;
			case "Bool": OcamlStandardIMapStringifier.ExactBool;
			case _: OcamlStandardIMapStringifier.DynamicObject;
		}
	}

	static function runtimeCapabilities(iterator:Bool, formatted:Bool, keyStringifier:Null<OcamlStandardIMapStringifier>,
			valueStringifier:Null<OcamlStandardIMapStringifier>):Array<String> {
		final out = [MAP_RUNTIME_CAPABILITY];
		if (iterator)
			out.push(ITERATOR_RUNTIME_CAPABILITY);
		if (!formatted)
			return out;
		out.push(ARRAY_RUNTIME_CAPABILITY);
		final stringifiers = [keyStringifier, valueStringifier];
		if (Lambda.exists(stringifiers, stringifier -> stringifier == OcamlStandardIMapStringifier.ExactString))
			out.push(STRING_TEXT_RUNTIME_CAPABILITY);
		if (Lambda.exists(stringifiers, stringifier -> stringifier == OcamlStandardIMapStringifier.DynamicObject))
			out.push(DYNAMIC_TEXT_RUNTIME_CAPABILITY);
		return out;
	}
}
#end
