package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapKeyKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapStringifier;

/** Stable source coordinates that contain no live compiler position object. */
typedef OcamlIMapInterfaceSourceSpan = {
	final file:String;
	final min:Int;
	final max:Int;
}

/** The source value whose behavior one `IMap` adapter preserves. */
enum abstract OcamlIMapInterfaceSourceKind(String) from String to String {
	final StandardStringMap = "standard-string-map";
	final StandardIntMap = "standard-int-map";
	final StandardObjectMap = "standard-object-map";
	final StandardStringMapAbstract = "standard-string-map-abstract";
	final StandardIntMapAbstract = "standard-int-map-abstract";
	final StandardObjectMapAbstract = "standard-object-map-abstract";
	final UserImplementation = "user-implementation";
}

/** The typed boundary at which a concrete value becomes an `IMap` value. */
enum abstract OcamlIMapInterfaceConversionRole(String) from String to String {
	final CallArgument = "call-argument";
	final ReturnValue = "return-value";
	final LocalInitializer = "local-initializer";
	final Assignment = "assignment";
}

/** One `IMap` method retained by Haxe dead-code elimination. */
typedef OcamlIMapInterfaceMethodDecision = {
	final name:String;
	final sourceOwnerModuleId:String;
	final sourceOwnerTypeName:String;
	final argumentSemanticTypeIds:Array<String>;
	final resultSemanticTypeId:String;
}

/**
	One explicit conversion from a concrete Map value to the target interface carrier.

	The carrier is an `Obj.t` containing the generated `haxe.IMap` dispatch record.
	Standard maps keep their existing `HxMap` storage behind closures. A user class
	keeps its original receiver and each closure invokes the class's checked method.
	No key type is used as proof that an arbitrary interface receiver is an `HxMap`.
**/
typedef OcamlIMapInterfaceConversionDecision = {
	final id:String;
	final source:OcamlIMapInterfaceSourceSpan;
	final role:OcamlIMapInterfaceConversionRole;
	final roleIndex:Int;
	final sourceKind:OcamlIMapInterfaceSourceKind;
	final sourceSemanticTypeId:String;
	final sourceCarrierTypeId:String;
	final targetSemanticTypeId:String;
	final targetCarrierTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final standardKeyKind:Null<OcamlStandardIMapKeyKind>;
	final keyStringifier:Null<OcamlStandardIMapStringifier>;
	final valueStringifier:Null<OcamlStandardIMapStringifier>;
	final methods:Array<OcamlIMapInterfaceMethodDecision>;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One method call through an already converted `IMap` carrier. */
typedef OcamlIMapInterfaceCallDecision = {
	final id:String;
	final source:OcamlIMapInterfaceSourceSpan;
	final operation:OcamlStandardIMapOperation;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final argumentSemanticTypeIds:Array<String>;
	final resultSemanticTypeId:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One approved raw-storage use of a compiler-generated `Map` expansion local. */
typedef OcamlIMapStorageAliasUseDecision = {
	final source:OcamlIMapInterfaceSourceSpan;
	final nativeOperation:String;
	final carrierTypeId:String;
}

/** How a proven standard Map storage alias handles a possible Haxe null. */
enum abstract OcamlIMapStorageAliasNullPolicy(String) from String to String {
	/** The typed source is an exact non-null `Map<K,V>`. */
	final NonNullableSource = "non-null-source";

	/** Check an `Obj.t` once, throw on null, then recover the exact Map carrier. */
	final CheckNullAndUnbox = "check-null-and-unbox";
}

/**
	A closed standard-library expansion that may keep native Map storage.

	Haxe's multi-type `Map<K,V>` abstract can introduce an `IMap<K,V>` local while
	inlining a concrete standard Map operation. This decision does not make
	`IMap` use raw storage generally. It proves that every read of this one local
	is immediately consumed by the matching target-authored `NativeHxMap`
	operation, so building an interface dispatch record would be both unnecessary
	and the wrong carrier for the following call.
**/
typedef OcamlIMapStorageAliasDecision = {
	final id:String;
	final source:OcamlIMapInterfaceSourceSpan;
	final sourceSemanticTypeId:String;
	final sourceCarrierTypeId:String;
	final preservedCarrierTypeId:String;
	final targetSemanticTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final standardKeyKind:OcamlStandardIMapKeyKind;
	final nullPolicy:OcamlIMapStorageAliasNullPolicy;
	final uses:Array<OcamlIMapStorageAliasUseDecision>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	Pure validation contract shared by target planning and saved-report inspection.

	This module contains no live Haxe compiler objects. The command-line inspector
	can therefore reject stale or edited evidence using the same carrier, method,
	and runtime rules that the compiler used before emitting OCaml.
**/
class OcamlIMapInterfaceContract {
	public static inline final MODEL = "typed-imap-interface-adapter-v3";
	public static inline final CONVERSION_PROOF_ID = "typed-imap-interface-conversion-v1";
	public static inline final CALL_PROOF_ID = "typed-imap-interface-dispatch-v1";
	public static inline final STORAGE_ALIAS_PROOF_ID = "typed-standard-map-storage-alias-v2";
	public static inline final TARGET_CARRIER_ID = "Obj.t(haxe_Constraints.imap_t)";
	public static inline final CONVERSION_PROOF_CLAIM = "The final typed Haxe occurrence converts either a canonical standard Map declaration or a class proven to implement the exact haxe.Constraints.IMap<K,V> interface into one dispatch record. Standard storage and user methods remain distinct; a key type never proves the runtime receiver implementation.";
	public static inline final CALL_PROOF_CLAIM = "The final typed Haxe call resolves to one method on the exact haxe.Constraints.IMap<K,V> declaration. The receiver is already the sealed interface carrier, so target syntax evaluates it once, evaluates arguments in source order, and invokes only the recorded dispatch field.";
	public static inline final STORAGE_ALIAS_PROOF_CLAIM = "The final typed local has exact haxe.Constraints.IMap<K,V> type. Its initializer is either an exact haxe.ds.Map<K,V> value or an exact static Null<Map<K,V>> field whose sealed storage carrier is Obj.t. A nullable source is evaluated once, checked for Haxe null, and recovered with checked Obj.obj into the exact standard Map carrier; null throws Haxe Null Access before native Map use. Every read of the local is the first argument of a matching target-authored haxe.ds.NativeHxMap operation behind the matching standard-map cast. The local has at least one such use and is never assigned, captured, returned, compared, dispatched through IMap, or consumed by another operation.";

	public static final REQUIRED_METHODS = [
		"get",
		"set",
		"exists",
		"remove",
		"keys",
		"iterator",
		"keyValueIterator",
		"copy",
		"toString",
		"clear"
	];

	/** Returns the complete interface operation surface in declaration order. */
	public static function requiredOperations():Array<OcamlStandardIMapOperation> {
		return [Get, Set, Exists, Remove, Keys, Values, Pairs, Copy, ToString, Clear];
	}

	/** Rejects a malformed or internally conflicting conversion record. */
	public static function requireConversion(decision:OcamlIMapInterfaceConversionDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.sourceSemanticTypeId.length == 0
			|| decision.sourceCarrierTypeId.length == 0
			|| decision.targetSemanticTypeId != 'haxe.IMap<${decision.keySemanticTypeId}, ${decision.valueSemanticTypeId}>'
			|| decision.targetCarrierTypeId != TARGET_CARRIER_ID
			|| decision.proofId != CONVERSION_PROOF_ID
			|| decision.proofClaim != CONVERSION_PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0
			|| !validConversionRole(decision.role, decision.roleIndex)) {
			throw "reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: conversion has incomplete type, source, proof, or revision facts";
		}
		final expectedKeyKind = standardKeyKind(decision.sourceKind);
		final standard = expectedKeyKind != null;
		final expectedKeyStringifier = standard ? OcamlStandardIMapCallContract.stringifierForSemanticTypeId(decision.keySemanticTypeId) : null;
		final expectedValueStringifier = standard ? OcamlStandardIMapCallContract.stringifierForSemanticTypeId(decision.valueSemanticTypeId) : null;
		final expectedCapabilities = standard ? OcamlStandardIMapCallContract.adapterRuntimeCapabilities(decision.keySemanticTypeId,
			decision.valueSemanticTypeId) : [];
		if (decision.standardKeyKind != expectedKeyKind
			|| decision.keyStringifier != expectedKeyStringifier
			|| decision.valueStringifier != expectedValueStringifier
			|| decision.runtimeCapabilities.join(",") != expectedCapabilities.join(",")) {
			throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: conversion "${decision.id}" has a conflicting source kind, method surface, or runtime inventory';
		}
		if (expectedKeyKind != null) {
			final keyKind:OcamlStandardIMapKeyKind = expectedKeyKind;
			if (!OcamlStandardIMapCallContract.keyKindMatchesSemanticType(keyKind, decision.keySemanticTypeId)
				|| decision.sourceCarrierTypeId != OcamlStandardIMapCallContract.carrierId(keyKind)
				|| decision.sourceSemanticTypeId != standardSourceSemanticTypeId(decision.sourceKind, decision.keySemanticTypeId,
					decision.valueSemanticTypeId)) {
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: conversion "${decision.id}" disagrees with its standard Map source and key carrier';
			}
		}
		var previousMethodIndex = -1;
		for (method in decision.methods) {
			final operation = operationForMethod(method.name);
			final methodIndex = REQUIRED_METHODS.indexOf(method.name);
			if (methodIndex <= previousMethodIndex
				|| method.sourceOwnerModuleId.length == 0
				|| method.sourceOwnerTypeName.length == 0
				|| operation == null) {
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: conversion "${decision.id}" has an incomplete or reordered retained method surface';
			}
			previousMethodIndex = methodIndex;
			final exactOperation:OcamlStandardIMapOperation = operation;
			if (method.argumentSemanticTypeIds.join(",") != OcamlStandardIMapCallContract.argumentSemanticTypeIds(exactOperation, decision.keySemanticTypeId,
				decision.valueSemanticTypeId)
				.join(",") || method.resultSemanticTypeId != OcamlStandardIMapCallContract.expectedResultSemanticTypeId(exactOperation,
					decision.targetSemanticTypeId, decision.keySemanticTypeId, decision.valueSemanticTypeId)) {
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: conversion "${decision.id}" has a retained method whose key, value, or result type disagrees with its IMap boundary';
			}
			if (standard && (method.sourceOwnerModuleId != "haxe.Constraints" || method.sourceOwnerTypeName != "IMap"))
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: standard conversion "${decision.id}" does not attribute its retained method to haxe.Constraints.IMap';
		}
	}

	/** Rejects a malformed interface-dispatch record. */
	public static function requireCall(decision:OcamlIMapInterfaceCallDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.keySemanticTypeId.length == 0
			|| decision.valueSemanticTypeId.length == 0
			|| decision.receiverSemanticTypeId != 'haxe.IMap<${decision.keySemanticTypeId}, ${decision.valueSemanticTypeId}>'
			|| decision.receiverCarrierTypeId != TARGET_CARRIER_ID
			|| OcamlStandardIMapCallContract.sourceFieldName(decision.operation).length == 0
			|| decision.argumentSemanticTypeIds.join(",") != OcamlStandardIMapCallContract.argumentSemanticTypeIds(decision.operation,
				decision.keySemanticTypeId, decision.valueSemanticTypeId)
				.join(",") || decision.resultSemanticTypeId != OcamlStandardIMapCallContract.expectedResultSemanticTypeId(decision.operation,
				decision.receiverSemanticTypeId, decision.keySemanticTypeId, decision.valueSemanticTypeId)
			|| decision.proofId != CALL_PROOF_ID
			|| decision.proofClaim != CALL_PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw "reflaxe.ocaml [ocaml-imap-interface:invalid-call]: call has incomplete type, source, proof, or revision facts";
		}
	}

	/** Rejects a storage alias that does not prove one closed standard Map expansion. */
	public static function requireStorageAlias(decision:OcamlIMapStorageAliasDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-imap-interface:invalid-storage-alias]: storage alias is missing";
		final mapSemanticTypeId = 'Map<${decision.keySemanticTypeId}, ${decision.valueSemanticTypeId}>';
		final expectedSourceSemanticTypeId = switch (decision.nullPolicy) {
			case NonNullableSource: mapSemanticTypeId;
			case CheckNullAndUnbox: 'Null<$mapSemanticTypeId>';
			case _: "";
		};
		final expectedCarrierTypeId = OcamlStandardIMapCallContract.carrierId(decision.standardKeyKind);
		final expectedSourceCarrierTypeId = switch (decision.nullPolicy) {
			case NonNullableSource: expectedCarrierTypeId;
			case CheckNullAndUnbox: "Obj.t";
			case _: "";
		};
		if (decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.keySemanticTypeId.length == 0
			|| decision.valueSemanticTypeId.length == 0
			|| decision.sourceSemanticTypeId != expectedSourceSemanticTypeId
			|| decision.targetSemanticTypeId != 'haxe.IMap<${decision.keySemanticTypeId}, ${decision.valueSemanticTypeId}>'
			|| decision.sourceCarrierTypeId != expectedSourceCarrierTypeId
			|| decision.preservedCarrierTypeId != expectedCarrierTypeId
			|| !OcamlStandardIMapCallContract.keyKindMatchesSemanticType(decision.standardKeyKind, decision.keySemanticTypeId)
			|| decision.uses.length == 0
			|| decision.proofId != STORAGE_ALIAS_PROOF_ID
			|| decision.proofClaim != STORAGE_ALIAS_PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw "reflaxe.ocaml [ocaml-imap-interface:invalid-storage-alias]: storage alias has incomplete type, source, use, proof, or revision facts";
		}
		var previousUse = "";
		for (use in decision.uses) {
			final useIdentity = '${use.source.file}:${use.source.min}:${use.source.max}:${use.nativeOperation}';
			if (use.source.file.length == 0
				|| use.source.min < 0
				|| use.source.max < use.source.min
				|| use.carrierTypeId != decision.preservedCarrierTypeId
				|| !validNativeStorageOperation(use.nativeOperation, decision.standardKeyKind)
				|| (previousUse.length > 0 && Reflect.compare(previousUse, useIdentity) >= 0)) {
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-storage-alias]: storage alias "${decision.id}" has an invalid, duplicate, or reordered native use';
			}
			previousUse = useIdentity;
		}
	}

	/** Stable runtime-requirement identities owned by one conversion occurrence. */
	public static function runtimeRequirementIds(decision:OcamlIMapInterfaceConversionDecision):Array<String> {
		requireConversion(decision);
		return decision.runtimeCapabilities.map(capability -> decision.id + ":runtime:" + capability);
	}

	static function validConversionRole(role:OcamlIMapInterfaceConversionRole, roleIndex:Int):Bool {
		return switch (role) {
			case CallArgument, LocalInitializer: roleIndex >= 0;
			case ReturnValue, Assignment: roleIndex == -1;
			case _: false;
		}
	}

	static function standardKeyKind(sourceKind:OcamlIMapInterfaceSourceKind):Null<OcamlStandardIMapKeyKind> {
		return switch (sourceKind) {
			case StandardStringMap, StandardStringMapAbstract: OcamlStandardIMapKeyKind.StringKey;
			case StandardIntMap, StandardIntMapAbstract: OcamlStandardIMapKeyKind.IntKey;
			case StandardObjectMap, StandardObjectMapAbstract: OcamlStandardIMapKeyKind.ObjectIdentityKey;
			case UserImplementation: null;
			case _: throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: unsupported IMap conversion source kind "$sourceKind"';
		}
	}

	static function standardSourceSemanticTypeId(sourceKind:OcamlIMapInterfaceSourceKind, keySemanticTypeId:String, valueSemanticTypeId:String):String {
		return switch (sourceKind) {
			case StandardStringMap, StandardIntMap: 'HxMap<$valueSemanticTypeId>';
			case StandardObjectMap: 'HxMap<$keySemanticTypeId, $valueSemanticTypeId>';
			case StandardStringMapAbstract, StandardIntMapAbstract, StandardObjectMapAbstract: 'Map<$keySemanticTypeId, $valueSemanticTypeId>';
			case UserImplementation: throw "reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: user IMap implementations have no standard source carrier";
			case _: throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: unsupported IMap conversion source kind "$sourceKind"';
		}
	}

	static function validNativeStorageOperation(operation:String, keyKind:OcamlStandardIMapKeyKind):Bool {
		final suffix = switch (keyKind) {
			case StringKey: "string";
			case IntKey: "int";
			case ObjectIdentityKey: "object";
			case _: return false;
		};
		if (!StringTools.endsWith(operation, "_" + suffix))
			return false;
		final prefix = operation.substr(0, operation.length - suffix.length - 1);
		return ["set", "get", "exists", "remove", "clear", "copy", "keys", "values", "pairs"].indexOf(prefix) >= 0;
	}

	static function operationForMethod(name:String):Null<OcamlStandardIMapOperation> {
		return switch (name) {
			case "set": OcamlStandardIMapOperation.Set;
			case "get": OcamlStandardIMapOperation.Get;
			case "exists": OcamlStandardIMapOperation.Exists;
			case "remove": OcamlStandardIMapOperation.Remove;
			case "keys": OcamlStandardIMapOperation.Keys;
			case "iterator": OcamlStandardIMapOperation.Values;
			case "keyValueIterator": OcamlStandardIMapOperation.Pairs;
			case "copy": OcamlStandardIMapOperation.Copy;
			case "toString": OcamlStandardIMapOperation.ToString;
			case "clear": OcamlStandardIMapOperation.Clear;
			case _: null;
		}
	}
}
#end
