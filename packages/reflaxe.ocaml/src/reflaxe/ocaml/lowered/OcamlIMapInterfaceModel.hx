package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapKeyKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapStringifier;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

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

	/**
		Stable identity for this role inside the owning function.

		Call arguments use `call-argument:<index>`, returns and assignments use
		fixed names, and local initializers use the lexical-local identity created
		from their source structure. A request-local Haxe `TVar.id` is never valid
		here because saved reports must survive a clean compiler process.
	**/
	final roleIdentity:String;

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
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
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
	public static inline final MODEL = "typed-imap-interface-adapter-v5";
	static inline final LEXICAL_LOCAL_ID_PREFIX = "lexical-local-v1:";
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
			|| decision.roleIdentity == null
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
			|| !validConversionRole(decision.role, decision.roleIdentity)) {
			throw "reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: conversion has incomplete type, source, proof, or revision facts";
		}
		final expectedKeyKind = standardKeyKind(decision.sourceKind);
		final standard = expectedKeyKind != null;
		if (!standard && decision.sourceKind != OcamlIMapInterfaceSourceKind.UserImplementation)
			throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-conversion]: conversion "${decision.id}" has an unknown source kind';
		final expectedKeyStringifier = standard ? OcamlStandardIMapCallContract.stringifierForSemanticTypeId(decision.keySemanticTypeId) : null;
		final expectedValueStringifier = standard ? OcamlStandardIMapCallContract.stringifierForSemanticTypeId(decision.valueSemanticTypeId) : null;
		final expectedCapabilities = adapterRuntimeCapabilities(decision.sourceKind, decision.keySemanticTypeId, decision.valueSemanticTypeId,
			decision.methods);
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
		final expectedUses = runtimeUseOccurrencesFor(decision);
		if (decision.runtimeUseOccurrences.length != expectedUses.length)
			throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-runtime-use]: conversion "${decision.id}" has an incomplete private-runtime occurrence inventory';
		for (index in 0...expectedUses.length)
			requireRuntimeUse(decision.id, index, decision.runtimeUseOccurrences[index], expectedUses[index]);
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

	/** Returns the exact runtime capability set for one complete adapter. */
	public static function adapterRuntimeCapabilities(sourceKind:OcamlIMapInterfaceSourceKind, keySemanticTypeId:String, valueSemanticTypeId:String,
			methods:Array<OcamlIMapInterfaceMethodDecision>):Array<String> {
		final standard = standardKeyKind(sourceKind) != null;
		if (standard)
			return OcamlStandardIMapCallContract.adapterRuntimeCapabilities(keySemanticTypeId, valueSemanticTypeId);
		final out = [OcamlStandardIMapCallContract.TYPE_RUNTIME_CAPABILITY];
		if (Lambda.exists(methods, method -> method.argumentSemanticTypeIds.contains("Bool")))
			out.push(OcamlStandardIMapCallContract.CORE_RUNTIME_CAPABILITY);
		return out;
	}

	/** Recomputes the ordered private names inserted by one adapter conversion. */
	public static function runtimeUseOccurrencesFor(decision:OcamlIMapInterfaceConversionDecision):Array<OcamlRuntimeUseOccurrence> {
		final planned:Array<{role:String, symbol:String}> = [{role: "type-marker", symbol: "HxType.class_"}];
		final keyKind = standardKeyKind(decision.sourceKind);
		for (method in decision.methods) {
			final operation = operationForMethod(method.name);
			if (operation == null)
				continue;
			for (index in 0...method.argumentSemanticTypeIds.length)
				if (method.argumentSemanticTypeIds[index] == "Bool")
					planned.push({role: 'decode-bool:${method.name}:$index', symbol: "HxRuntime.unbox_bool_or_obj"});
			if (keyKind == null)
				continue;
			planned.push({
				role: 'standard-map:${method.name}',
				symbol: "HxMap." + OcamlStandardIMapCallContract.runtimeFunction(operation, keyKind)
			});
			switch (operation) {
				case Keys, Values, Pairs:
					planned.push({role: 'wrap-iterator:${method.name}', symbol: "HxIterator.of_array"});
				case ToString:
					planned.push({role: "format-next", symbol: "HxIterator.next"});
					appendStringifierUse(planned, "format-key", decision.keyStringifier);
					appendStringifierUse(planned, "format-value", decision.valueStringifier);
					planned.push({role: "format-push", symbol: "HxArray.push"});
					planned.push({role: "format-has-next", symbol: "HxIterator.hasNext"});
					planned.push({role: "format-join", symbol: "HxArray.join"});
					planned.push({role: "format-of-array", symbol: "HxIterator.of_array"});
					planned.push({role: "format-create-array", symbol: "HxArray.create"});
				case _:
			}
		}
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final requirementIds = decision.runtimeCapabilities.map(capability -> decision.id + ":runtime:" + capability);
		return [
			for (index in 0...planned.length) {
				final item = planned[index];
				final capability = capabilityForSymbol(item.symbol);
				final capabilityIndex = decision.runtimeCapabilities.indexOf(capability);
				if (capabilityIndex < 0)
					throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-runtime-use]: conversion "${decision.id}" has no requirement for ${item.symbol}';
				{
					id: '${decision.id}:runtime-use:$index:${item.role}',
					planRevision: OcamlRuntimeUseModel.planRevision(binding),
					ownerId: decision.id,
					requirementId: requirementIds[capabilityIndex],
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: item.symbol,
					role: item.role,
					order: index,
					source: {
						file: decision.source.file,
						min: decision.source.min,
						max: decision.source.max
					},
					profileEligibility: ["metal", "portable"],
					cardinality: 1
				};
			}
		];
	}

	static function appendStringifierUse(planned:Array<{role:String, symbol:String}>, role:String, stringifier:Null<OcamlStandardIMapStringifier>):Void {
		switch (stringifier) {
			case ExactString:
				planned.push({role: role, symbol: "HxString.toStdString"});
			case DynamicObject:
				planned.push({role: role, symbol: "HxDynamic.toStdString"});
			case ExactInt, ExactFloat, ExactBool, null:
		}
	}

	static function capabilityForSymbol(symbol:String):String {
		final root = symbol.substr(0, symbol.indexOf("."));
		return switch (root) {
			case "HxMap": OcamlStandardIMapCallContract.MAP_RUNTIME_CAPABILITY;
			case "HxIterator": OcamlStandardIMapCallContract.ITERATOR_RUNTIME_CAPABILITY;
			case "HxArray": OcamlStandardIMapCallContract.ARRAY_RUNTIME_CAPABILITY;
			case "HxString": OcamlStandardIMapCallContract.STRING_TEXT_RUNTIME_CAPABILITY;
			case "HxDynamic": OcamlStandardIMapCallContract.DYNAMIC_TEXT_RUNTIME_CAPABILITY;
			case "HxType": OcamlStandardIMapCallContract.TYPE_RUNTIME_CAPABILITY;
			case "HxRuntime": OcamlStandardIMapCallContract.CORE_RUNTIME_CAPABILITY;
			case _: throw 'Unknown IMap adapter runtime symbol "$symbol".';
		}
	}

	static function requireRuntimeUse(ownerId:String, index:Int, actual:OcamlRuntimeUseOccurrence, expected:OcamlRuntimeUseOccurrence):Void {
		if (actual == null
			|| actual.id != expected.id
			|| actual.planRevision != expected.planRevision
			|| actual.ownerId != expected.ownerId
			|| actual.requirementId != expected.requirementId
			|| actual.domain != expected.domain
			|| actual.exactSymbol != expected.exactSymbol
			|| actual.role != expected.role
			|| actual.order != expected.order
			|| actual.source.file != expected.source.file
			|| actual.source.min != expected.source.min
			|| actual.source.max != expected.source.max
			|| actual.profileEligibility.join(",") != expected.profileEligibility.join(",")
			|| actual.cardinality != expected.cardinality)
			throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-runtime-use]: conversion "$ownerId" has a stale, missing, reordered, or conflicting runtime use at index $index';
	}

	static function validConversionRole(role:OcamlIMapInterfaceConversionRole, roleIdentity:String):Bool {
		return switch (role) {
			case CallArgument: StringTools.startsWith(roleIdentity, "call-argument:") && validNonNegativeIndex(roleIdentity.substr("call-argument:".length));
			case LocalInitializer:
				isReusableLexicalLocalId(roleIdentity);
			case ReturnValue:
				roleIdentity == "return-value";
			case Assignment:
				roleIdentity == "assignment";
			case _: false;
		}
	}

	/**
		Checks the generic lexical-local identity without loading Reflaxe itself.

		This pure report model is also used by small standalone tooling tests. The
		compiler creates the value through `LexicalLocalIdentityPlan`; inspection
		only needs to reject a temporary number, malformed digest, or other schema.
	**/
	static function isReusableLexicalLocalId(value:String):Bool {
		if (!StringTools.startsWith(value, LEXICAL_LOCAL_ID_PREFIX) || value.length != LEXICAL_LOCAL_ID_PREFIX.length + 64)
			return false;
		for (index in LEXICAL_LOCAL_ID_PREFIX.length...value.length) {
			final code = value.charCodeAt(index);
			final isDigit = code != null && code >= 48 && code <= 57;
			final isLowerHex = code != null && code >= 97 && code <= 102;
			if (!isDigit && !isLowerHex)
				return false;
		}
		return true;
	}

	static function validNonNegativeIndex(value:String):Bool {
		if (value.length == 0)
			return false;
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			if (code == null || code < 48 || code > 57)
				return false;
		}
		return true;
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
