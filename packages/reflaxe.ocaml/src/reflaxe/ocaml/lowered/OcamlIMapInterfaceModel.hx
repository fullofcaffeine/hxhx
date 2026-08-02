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

/**
	Pure validation contract shared by target planning and saved-report inspection.

	This module contains no live Haxe compiler objects. The command-line inspector
	can therefore reject stale or edited evidence using the same carrier, method,
	and runtime rules that the compiler used before emitting OCaml.
**/
class OcamlIMapInterfaceContract {
	public static inline final MODEL = "typed-imap-interface-adapter-v1";
	public static inline final CONVERSION_PROOF_ID = "typed-imap-interface-conversion-v1";
	public static inline final CALL_PROOF_ID = "typed-imap-interface-dispatch-v1";
	public static inline final TARGET_CARRIER_ID = "Obj.t(haxe_Constraints.imap_t)";
	public static inline final CONVERSION_PROOF_CLAIM = "The final typed Haxe occurrence converts either a canonical standard Map declaration or a class proven to implement the exact haxe.Constraints.IMap<K,V> interface into one dispatch record. Standard storage and user methods remain distinct; a key type never proves the runtime receiver implementation.";
	public static inline final CALL_PROOF_CLAIM = "The final typed Haxe call resolves to one method on the exact haxe.Constraints.IMap<K,V> declaration. The receiver is already the sealed interface carrier, so target syntax evaluates it once, evaluates arguments in source order, and invokes only the recorded dispatch field.";

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
			case StandardStringMap: OcamlStandardIMapKeyKind.StringKey;
			case StandardIntMap: OcamlStandardIMapKeyKind.IntKey;
			case StandardObjectMap: OcamlStandardIMapKeyKind.ObjectIdentityKey;
			case UserImplementation: null;
			case _: throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: unsupported IMap conversion source kind "$sourceKind"';
		}
	}

	static function standardSourceSemanticTypeId(sourceKind:OcamlIMapInterfaceSourceKind, keySemanticTypeId:String, valueSemanticTypeId:String):String {
		return switch (sourceKind) {
			case StandardStringMap, StandardIntMap: 'HxMap<$valueSemanticTypeId>';
			case StandardObjectMap: 'HxMap<$keySemanticTypeId, $valueSemanticTypeId>';
			case UserImplementation: throw "reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: user IMap implementations have no standard source carrier";
			case _: throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: unsupported IMap conversion source kind "$sourceKind"';
		}
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
