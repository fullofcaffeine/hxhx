package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
#if macro
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorOperation;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallTarget;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The caller-visible meaning selected for one field that overlaps a target protocol. */
enum abstract OcamlStructuralFieldOperation(String) from String to String {
	/** Read an ordinary stored field from the portable anonymous-object carrier. */
	final ReadStoredField = "read-stored-field";

	/** Replace an ordinary stored field and return the assigned Haxe value. */
	final WriteStoredField = "write-stored-field";

	/** Capture a genuine structural Iterator method as a `Void -> T` value. */
	final CaptureIteratorMethod = "capture-iterator-method";

	/** Read `key` from a pair produced by the target's standard map iterator. */
	final ProjectTupleKey = "project-tuple-key";

	/** Read `value` from a pair produced by the target's standard map iterator. */
	final ProjectTupleValue = "project-tuple-value";
}

/** How a stored `HxAnon` value becomes the field's typed Haxe result. */
enum abstract OcamlStructuralFieldLoadConversion(String) from String to String {
	final ObjObj = "obj-obj";
	final UnboxBool = "unbox-bool";
}

/** How an assigned Haxe value enters the universal `HxAnon` field slot. */
enum abstract OcamlStructuralFieldStoreConversion(String) from String to String {
	final ObjRepr = "obj-repr";
	final BoxBool = "box-bool";
}

/**
	Proof that one anonymous `{key, value}` receiver uses the OCaml tuple carrier.

	Haxe erases the pair's `KeyValueIterator<K,V>` typedef after `next()` returns,
	so the field receiver alone looks like any other anonymous object. These facts
	retain the producer identity, the typed `next()` call, and stable locals that
	connect the pair back to either a standard `IMap.keyValueIterator()` call or
	the target's exact standard-Map pair helper. Syntax may use `fst` or `snd` only
	when this complete chain was sealed from the final typed body.
**/
typedef OcamlKeyValueTupleProjectionTarget = {
	final projection:String;
	final iteratorProducerKind:String;
	final iteratorProducerId:String;
	final iteratorProducerSourceId:String;
	final pairProducerCallId:String;
	final iteratorLocalId:String;
	final pairLocalId:String;
	final iteratorSemanticTypeId:String;
	final pairSemanticTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final proofId:String;
	final proofClaim:String;
}

/**
	One immutable decision for a field whose spelling overlaps a target protocol.

	The decision makes the important distinction before OCaml syntax: `q.next`
	can be an ordinary linked-node value, while `iterator.next` can be a captured
	Iterator method. It also distinguishes ordinary stored `key` and `value`
	fields from pair projections produced by the standard map iterator. The
	renderer receives the selected operation and is not allowed to infer any of
	these meanings from the spelling of the field.
**/
typedef OcamlStructuralFieldDecision = {
	final id:String;
	final occurrenceOrdinal:Int;
	final source:OcamlLoweredSourceSpan;
	final operation:OcamlStructuralFieldOperation;
	final fieldName:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final fieldSemanticTypeId:String;
	final resultSemanticTypeId:String;
	final loadConversion:Null<OcamlStructuralFieldLoadConversion>;
	final storeConversion:Null<OcamlStructuralFieldStoreConversion>;
	final runtimeModule:String;
	final runtimeOperation:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final evaluationSchedule:Array<String>;
	final iteratorTarget:Null<OcamlStructuralIteratorCallTarget>;
	final keyValueTupleTarget:Null<OcamlKeyValueTupleProjectionTarget>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Pure identity and validation rules shared by planning, syntax, and reports. */
class OcamlStructuralFieldContract {
	public static inline final MODEL = "typed-structural-field-overlap-v4";
	public static inline final HAXE_ANON_CAPABILITY = "haxe-structural-field";
	public static inline final HAXE_BOOL_CARRIER_CAPABILITY = "haxe-structural-bool-carrier";
	public static inline final HAXE_ITERATOR_CAPABILITY = "haxe-iterator";
	public static inline final STORED_PROOF_ID = "structural-stored-field-v1";
	public static inline final ITERATOR_PROOF_ID = "structural-iterator-method-value-v1";
	public static inline final KEY_VALUE_TUPLE_PROOF_ID = "standard-map-key-value-tuple-projection-v3";
	public static inline final TARGET_NATIVE_MAP_PAIR_PRODUCER_PROOF_ID = "target-native-standard-map-pair-producer-v1";

	public static inline final STORED_PROOF_CLAIM = "The final typed FAnon occurrence names an ordinary stored next, hasNext, key, or value field, not a complete structural Iterator method or a pair produced by the standard IMap keyValueIterator path. The portable carrier is one HxAnon object. Reads evaluate the receiver once and recover the stored field value. Writes evaluate the receiver before the assigned value, replace that exact field, and return the assigned Haxe value.";
	public static inline final ITERATOR_PROOF_CLAIM = "The final typed field occurrence captures hasNext or next from a complete structural Iterator value. The target evaluates the receiver once and returns a zero-argument closure over the exact HxIterator operation. Immediate invocation remains owned by the separate structural Iterator call plan.";
	public static inline final KEY_VALUE_TUPLE_PROOF_CLAIM = "The final typed key or value read receives a pair from structural Iterator.next, whose unchanged iterator local receives either a sealed IMap interface keyValueIterator call, the earlier standard-IMap call form, or the exact target-authored NativeHxMapIterator.of_array call around a typed NativeHxMap pair helper. Stable lexical locals, the typed producer identity, and the sealed next-call identity connect the anonymous pair back to that producer before syntax. No field name or anonymous shape authorizes the tuple projection.";

	/** Returns whether this bounded model owns a potentially ambiguous field. */
	public static function ownsFieldName(name:String):Bool {
		return name == "next" || name == "hasNext" || name == "key" || name == "value";
	}

	/** Returns the one runtime requirement selected by a structural field decision. */
	public static function runtimeRequirementId(decisionId:String, operation:OcamlStructuralFieldOperation):String {
		return decisionId + ":runtime:" + (operation == CaptureIteratorMethod ? HAXE_ITERATOR_CAPABILITY : HAXE_ANON_CAPABILITY);
	}

	/** Returns the extra direct-root requirement for a stored Boolean conversion. */
	public static function boolCarrierRuntimeRequirementId(decisionId:String):String {
		return decisionId + ":runtime:" + HAXE_BOOL_CARRIER_CAPABILITY;
	}

	/** Returns every direct runtime root selected by one structural-field decision. */
	public static function runtimeRequirementIdsFor(decision:OcamlStructuralFieldDecision):Array<String> {
		if (isTupleProjection(decision.operation))
			return [];
		final result = [runtimeRequirementId(decision.id, decision.operation)];
		if (decision.loadConversion == UnboxBool || decision.storeConversion == BoxBool)
			result.push(boolCarrierRuntimeRequirementId(decision.id));
		return result;
	}

	/**
		Builds the private runtime names that target syntax must consume.

		Order follows traversal of the completed target expression. This lets the
		caller inspect the actual field-owned syntax without entering receiver or
		assigned-value expressions, which can have independent plan owners.
	**/
	public static function runtimeUseOccurrencesFor(decision:OcamlStructuralFieldDecision):Array<OcamlRuntimeUseOccurrence> {
		if (isTupleProjection(decision.operation))
			return [];
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final result = new Array<OcamlRuntimeUseOccurrence>();

		function add(requirementId:String, exactSymbol:String, role:String):Void {
			result.push({
				id: decision.id + ":runtime-use:" + role,
				planRevision: planRevision,
				ownerId: decision.id,
				requirementId: requirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: exactSymbol,
				role: role,
				order: result.length,
				source: {
					file: decision.source.file,
					min: decision.source.min,
					max: decision.source.max
				},
				profileEligibility: ["metal", "portable"],
				cardinality: 1
			});
		}

		final operationRequirement = runtimeRequirementId(decision.id, decision.operation);
		switch (decision.operation) {
			case ReadStoredField:
				if (decision.loadConversion == UnboxBool)
					add(boolCarrierRuntimeRequirementId(decision.id), "HxRuntime.unbox_bool_or_obj", "unbox-bool");
				add(operationRequirement, decision.runtimeModule + "." + decision.runtimeOperation, "read-field");
			case WriteStoredField:
				add(operationRequirement, decision.runtimeModule + "." + decision.runtimeOperation, "write-field");
				if (decision.storeConversion == BoxBool)
					add(boolCarrierRuntimeRequirementId(decision.id), "HxRuntime.box_bool", "box-bool");
			case CaptureIteratorMethod:
				add(operationRequirement, decision.runtimeModule + "." + decision.runtimeOperation, "capture-iterator-method");
			case ProjectTupleKey, ProjectTupleValue:
		}
		return result;
	}

	/** Returns whether the decision uses only an OCaml Stdlib tuple projection. */
	public static function isTupleProjection(operation:OcamlStructuralFieldOperation):Bool {
		return operation == ProjectTupleKey || operation == ProjectTupleValue;
	}

	/** Builds the content identity after every behavior-bearing field is known. */
	public static function decisionId(decision:OcamlStructuralFieldDecision):String {
		return "structural-field:" + Sha256.encode(semanticFingerprint(decision)).substr(0, 24);
	}

	/** Rejects missing, contradictory, or stale plain decision data. */
	public static function require(decision:OcamlStructuralFieldDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-structural-field:missing]: structural field decision is missing";
		if (!ownsFieldName(decision.fieldName)
			|| decision.occurrenceOrdinal < 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.receiverSemanticTypeId.length == 0
			|| decision.receiverCarrierTypeId.length == 0
			|| decision.fieldSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId.length == 0
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid]: structural field decision "${decision.id}" has incomplete source, type, or revision facts';
		}

		switch (decision.operation) {
			case ReadStoredField:
				requireStored(decision, "get", ["materialize-receiver", "read-field"], true);
			case WriteStoredField:
				requireStored(decision, "set", ["materialize-receiver", "materialize-value", "write-field"], false);
			case CaptureIteratorMethod:
				final target = decision.iteratorTarget;
				if (target == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:invalid-iterator]: Iterator method decision "${decision.id}" has no target';
				OcamlStructuralIteratorCallContract.require(target);
				if (decision.receiverSemanticTypeId != target.receiverSemanticTypeId
					|| decision.receiverCarrierTypeId != OcamlStructuralIteratorCallContract.RECEIVER_CARRIER
					|| decision.fieldName != OcamlStructuralIteratorCallContract.sourceFieldName(target.operation)
					|| decision.resultSemanticTypeId != decision.fieldSemanticTypeId
					|| decision.runtimeModule != target.runtimeModule
					|| decision.runtimeOperation != target.runtimeFunction
					|| target.proofId != OcamlStructuralIteratorCallContract.METHOD_VALUE_PROOF_ID
					|| target.proofClaim != OcamlStructuralIteratorCallContract.METHOD_VALUE_PROOF_CLAIM
					|| decision.loadConversion != null
					|| decision.storeConversion != null
					|| decision.keyValueTupleTarget != null
					|| decision.evaluationSchedule.join(",") != "materialize-receiver,capture-method"
					|| decision.proofId != ITERATOR_PROOF_ID
					|| decision.proofClaim != ITERATOR_PROOF_CLAIM) {
					throw 'reflaxe.ocaml [ocaml-structural-field:invalid-iterator]: Iterator method decision "${decision.id}" disagrees with its target';
				}
			case ProjectTupleKey, ProjectTupleValue:
				requireTupleProjection(decision);
		}
		final expectedRequirements = runtimeRequirementIdsFor(decision);
		if (decision.runtimeRequirementIds.join(",") != expectedRequirements.join(","))
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid-runtime]: structural field decision "${decision.id}" does not own its exact direct-root runtime requirements';
		final expectedUses = runtimeUseOccurrencesFor(decision);
		if (decision.runtimeUseOccurrences.length != expectedUses.length)
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid-runtime-use]: structural field decision "${decision.id}" does not own every target runtime use';
		for (index in 0...expectedUses.length)
			requireRuntimeUse(decision.id, index, decision.runtimeUseOccurrences[index], expectedUses[index]);
		if (decision.id != decisionId(decision))
			throw 'reflaxe.ocaml [ocaml-structural-field:stale]: structural field decision "${decision.id}" does not match its canonical facts';
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
			|| actual.cardinality != expected.cardinality) {
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid-runtime-use]: structural field decision "$ownerId" has a stale, missing, reordered, or conflicting runtime use at index $index';
		}
	}

	static function requireStored(decision:OcamlStructuralFieldDecision, operation:String, schedule:Array<String>, read:Bool):Void {
		final boolField = decision.fieldSemanticTypeId == "Bool";
		if (decision.receiverCarrierTypeId != "Obj.t"
			|| decision.resultSemanticTypeId != decision.fieldSemanticTypeId
			|| decision.runtimeModule != "HxAnon"
			|| decision.runtimeOperation != operation
			|| decision.evaluationSchedule.join(",") != schedule.join(",")
			|| decision.iteratorTarget != null
			|| decision.keyValueTupleTarget != null
			|| decision.proofId != STORED_PROOF_ID
			|| decision.proofClaim != STORED_PROOF_CLAIM
			|| (read && decision.storeConversion != null)
			|| (!read && decision.loadConversion != null)
			|| (read && decision.loadConversion != (boolField ? UnboxBool : ObjObj))
			|| (!read && decision.storeConversion != (boolField ? BoxBool : ObjRepr))) {
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid-stored]: stored field decision "${decision.id}" disagrees with its HxAnon operation';
		}
	}

	static function requireTupleProjection(decision:OcamlStructuralFieldDecision):Void {
		final target = decision.keyValueTupleTarget;
		if (target == null)
			throw 'reflaxe.ocaml [ocaml-structural-field:missing-key-value-proof]: tuple projection "${decision.id}" has no typed producer chain';
		final expectedProjection = decision.operation == ProjectTupleKey ? "fst" : "snd";
		final expectedField = decision.operation == ProjectTupleKey ? "key" : "value";
		final expectedFieldType = decision.operation == ProjectTupleKey ? target.keySemanticTypeId : target.valueSemanticTypeId;
		if ((target.projection != "fst" && target.projection != "snd")
			|| target.projection != expectedProjection
			|| decision.fieldName != expectedField
			|| decision.receiverSemanticTypeId != target.pairSemanticTypeId
			|| decision.receiverCarrierTypeId != 'tuple<${target.keySemanticTypeId},${target.valueSemanticTypeId}>'
			|| decision.fieldSemanticTypeId != expectedFieldType
			|| decision.resultSemanticTypeId != expectedFieldType
			|| decision.loadConversion != null
			|| decision.storeConversion != null
			|| decision.iteratorTarget != null
			|| decision.runtimeModule != "Stdlib"
			|| decision.runtimeOperation != expectedProjection
			|| decision.evaluationSchedule.join(",") != "materialize-receiver,project-field"
			|| decision.proofId != KEY_VALUE_TUPLE_PROOF_ID
			|| decision.proofClaim != KEY_VALUE_TUPLE_PROOF_CLAIM
			|| target.proofId != KEY_VALUE_TUPLE_PROOF_ID
			|| target.proofClaim != KEY_VALUE_TUPLE_PROOF_CLAIM
			|| !validIteratorProducer(target)
			|| target.pairProducerCallId.length == 0
			|| target.iteratorSemanticTypeId.length == 0
			|| target.pairSemanticTypeId.length == 0
			|| target.keySemanticTypeId.length == 0
			|| target.valueSemanticTypeId.length == 0
			|| !isReusableLocalId(target.iteratorLocalId)
			|| !isReusableLocalId(target.pairLocalId)) {
			throw 'reflaxe.ocaml [ocaml-structural-field:invalid-key-value-proof]: tuple projection "${decision.id}" disagrees with its typed producer chain';
		}
	}

	static function validIteratorProducer(target:OcamlKeyValueTupleProjectionTarget):Bool {
		return switch (target.iteratorProducerKind) {
			case "imap-interface-call": StringTools.startsWith(target.iteratorProducerId,
					"imap-interface-call:") && target.iteratorProducerSourceId == "haxe.Constraints.IMap.keyValueIterator";
			case "standard-imap-call": StringTools.startsWith(target.iteratorProducerId,
					"call:") && target.iteratorProducerSourceId == "haxe.Constraints.IMap.keyValueIterator";
			case "target-native-standard-map-call": final sourceMatchesKey = switch (target.iteratorProducerSourceId) {
					case "haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_string)": target.keySemanticTypeId == "String";
					case "haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_int)": target.keySemanticTypeId == "Int";
					case "haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.pairs_object)": target.keySemanticTypeId != "String" && target.keySemanticTypeId != "Int";
					case _: false;
				} target.iteratorProducerId == TARGET_NATIVE_MAP_PAIR_PRODUCER_PROOF_ID && sourceMatchesKey;
			case _:
				false;
		}
	}

	static function isReusableLocalId(localId:String):Bool {
		return ~/^lexical-local-v1:[0-9a-f]{64}$/.match(localId);
	}

	/** Returns a detached copy suitable for reports and sealed-plan storage. */
	public static function copy(decision:OcamlStructuralFieldDecision, ?id:String):OcamlStructuralFieldDecision {
		return {
			id: id ?? decision.id,
			occurrenceOrdinal: decision.occurrenceOrdinal,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			operation: decision.operation,
			fieldName: decision.fieldName,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			fieldSemanticTypeId: decision.fieldSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			loadConversion: decision.loadConversion,
			storeConversion: decision.storeConversion,
			runtimeModule: decision.runtimeModule,
			runtimeOperation: decision.runtimeOperation,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(use -> {
				id: use.id,
				planRevision: use.planRevision,
				ownerId: use.ownerId,
				requirementId: use.requirementId,
				domain: use.domain,
				exactSymbol: use.exactSymbol,
				role: use.role,
				order: use.order,
				source: {
					file: use.source.file,
					min: use.source.min,
					max: use.source.max
				},
				profileEligibility: use.profileEligibility.copy(),
				cardinality: use.cardinality
			}),
			evaluationSchedule: decision.evaluationSchedule.copy(),
			iteratorTarget: decision.iteratorTarget == null ? null : OcamlStructuralIteratorCallContract.copy(decision.iteratorTarget),
			keyValueTupleTarget: decision.keyValueTupleTarget == null ? null : copyKeyValueTupleTarget(decision.keyValueTupleTarget),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	/** Returns a detached copy of a tuple-projection producer proof. */
	public static function copyKeyValueTupleTarget(target:OcamlKeyValueTupleProjectionTarget):OcamlKeyValueTupleProjectionTarget {
		return {
			projection: target.projection,
			iteratorProducerKind: target.iteratorProducerKind,
			iteratorProducerId: target.iteratorProducerId,
			iteratorProducerSourceId: target.iteratorProducerSourceId,
			pairProducerCallId: target.pairProducerCallId,
			iteratorLocalId: target.iteratorLocalId,
			pairLocalId: target.pairLocalId,
			iteratorSemanticTypeId: target.iteratorSemanticTypeId,
			pairSemanticTypeId: target.pairSemanticTypeId,
			keySemanticTypeId: target.keySemanticTypeId,
			valueSemanticTypeId: target.valueSemanticTypeId,
			proofId: target.proofId,
			proofClaim: target.proofClaim
		};
	}

	/** Canonical text for the typed producer chain behind one tuple projection. */
	public static function keyValueTupleFingerprint(target:OcamlKeyValueTupleProjectionTarget):String {
		return [
			target.projection,
			target.iteratorProducerKind,
			target.iteratorProducerId,
			target.iteratorProducerSourceId,
			target.pairProducerCallId,
			target.iteratorLocalId,
			target.pairLocalId,
			target.iteratorSemanticTypeId,
			target.pairSemanticTypeId,
			target.keySemanticTypeId,
			target.valueSemanticTypeId,
			target.proofId,
			target.proofClaim
		].join("|");
	}

	/** Canonical semantic text used by decision IDs before derived runtime facts exist. */
	static function semanticFingerprint(decision:OcamlStructuralFieldDecision):String {
		return [
			Std.string(decision.occurrenceOrdinal),
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.operation : String),
			decision.fieldName,
			decision.receiverSemanticTypeId,
			decision.receiverCarrierTypeId,
			decision.fieldSemanticTypeId,
			decision.resultSemanticTypeId,
			decision.loadConversion == null ? "" : (decision.loadConversion : String),
			decision.storeConversion == null ? "" : (decision.storeConversion : String),
			decision.runtimeModule + "." + decision.runtimeOperation,
			decision.evaluationSchedule.join(","),
			decision.iteratorTarget == null ? "" : OcamlStructuralIteratorCallContract.fingerprint(decision.iteratorTarget),
			decision.keyValueTupleTarget == null ? "" : keyValueTupleFingerprint(decision.keyValueTupleTarget),
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	/** Canonical text used by complete-plan revisions after runtime uses are sealed. */
	public static function fingerprint(decision:OcamlStructuralFieldDecision):String {
		final runtimeUses = decision.runtimeUseOccurrences.map(use -> [
			use.id,
			use.planRevision,
			use.ownerId,
			use.requirementId,
			(use.domain : String),
			use.exactSymbol,
			use.role,
			Std.string(use.order),
			use.source.file,
			Std.string(use.source.min),
			Std.string(use.source.max),
			use.profileEligibility.join(","),
			Std.string(use.cardinality)
		].join("|")).join("\u001e");
		return [
			semanticFingerprint(decision),
			decision.runtimeRequirementIds.join(","),
			runtimeUses
		].join("|");
	}
}

#if macro
private typedef OcamlStructuralFieldOccurrence = {
	final expression:TypedExpr;
	final decisionId:String;
}

private typedef OcamlTupleIteratorLocalProof = {
	final producerKind:String;
	final producerId:String;
	final producerSourceId:String;
	final iteratorLocalId:String;
	final iteratorSemanticTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
}

private typedef OcamlTuplePairLocalProof = {
	final iterator:OcamlTupleIteratorLocalProof;
	final pairProducerCallId:String;
	final pairLocalId:String;
	final pairSemanticTypeId:String;
}

private typedef OcamlLocalInitializer = {
	final hostLocalId:Int;
	final semanticTypeId:String;
	final resolvedSemanticTypeId:String;
	final expression:TypedExpr;
}

/** Request-local lookup from final typed occurrences to immutable field decisions. */
class OcamlStructuralFieldPlan {
	final decisionsById:Map<String, OcamlStructuralFieldDecision> = [];
	final decisionIdByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
	final ordered:Array<OcamlStructuralFieldDecision>;

	public final revision:String;

	public function new(decisions:Array<OcamlStructuralFieldDecision>, ?occurrences:Array<OcamlStructuralFieldOccurrence>) {
		ordered = decisions.map(decision -> OcamlStructuralFieldContract.copy(decision));
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in ordered) {
			OcamlStructuralFieldContract.require(decision);
			if (decisionsById.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-structural-field:duplicate]: decision "${decision.id}" appears more than once';
			decisionsById.set(decision.id, OcamlStructuralFieldContract.copy(decision));
		}
		final seen:Map<String, Bool> = [];
		for (occurrence in occurrences ?? []) {
			if (decisionIdByExpression.exists(occurrence.expression)
				|| seen.exists(occurrence.decisionId)
				|| !decisionsById.exists(occurrence.decisionId))
				throw 'reflaxe.ocaml [ocaml-structural-field:occurrence]: structural field occurrence has a duplicate or missing decision "${occurrence.decisionId}"';
			decisionIdByExpression.set(occurrence.expression, occurrence.decisionId);
			seen.set(occurrence.decisionId, true);
		}
		if (occurrences != null)
			for (decision in ordered)
				if (!seen.exists(decision.id))
					throw 'reflaxe.ocaml [ocaml-structural-field:occurrence]: decision "${decision.id}" has no exact typed occurrence';
		revision = "sha256:" + Sha256.encode(ordered.map(OcamlStructuralFieldContract.fingerprint).join("\n"));
	}

	/** Returns and rechecks the decision for one exact final typed expression. */
	public function decisionFor(expression:TypedExpr):Null<OcamlStructuralFieldDecision> {
		final id = decisionIdByExpression.get(expression);
		if (id == null)
			return null;
		final decision = decisionsById.get(id);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-structural-field:stale]: decision "$id" is missing from its sealed plan';
		final mismatch = OcamlStructuralFieldPlanner.mismatchReason(decision, expression);
		if (mismatch != null)
			throw 'reflaxe.ocaml [ocaml-structural-field:stale]: decision "$id" no longer matches its final typed occurrence at ${decision.source.file}:${decision.source.min}-${decision.source.max}: $mismatch';
		return OcamlStructuralFieldContract.copy(decision);
	}

	/** Revalidates every decision against the function revision that owns it. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-structural-field:stale]: decision "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
	}

	/** Returns report-safe copies in stable identity order. */
	public function decisions():Array<OcamlStructuralFieldDecision> {
		return ordered.map(decision -> OcamlStructuralFieldContract.copy(decision));
	}
}

/** Selects overlapping structural fields from one exact final typed body. */
class OcamlStructuralFieldPlanner {
	final binding:OcamlFunctionPlanBinding;
	final calls:OcamlCallPlan;
	final iMapInterfaces:OcamlIMapInterfacePlan;
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final representations:OcamlRepresentationRegistry;
	final localIdentities:LexicalLocalIdentityPlan;
	var tuplePairsByHostLocalId:Map<Int, OcamlTuplePairLocalProof> = [];
	var ordinal = 0;

	public function new(binding:OcamlFunctionPlanBinding, calls:OcamlCallPlan, iMapInterfaces:OcamlIMapInterfacePlan,
			anonymousStructures:OcamlAnonymousStructurePlan, representations:OcamlRepresentationRegistry, localIdentities:LexicalLocalIdentityPlan) {
		this.binding = binding;
		this.calls = calls;
		this.iMapInterfaces = iMapInterfaces;
		this.anonymousStructures = anonymousStructures;
		this.representations = representations;
		this.localIdentities = localIdentities;
	}

	/**
		Plans stored fields, Iterator method values, and proven Map-pair fields.

		A Map pair is admitted only when two existing typed call decisions form a
		complete chain: a local receives `IMap.keyValueIterator()`, then another
		local receives `next()` from that unchanged iterator local. This early
		ownership step is what lets syntax use an OCaml tuple for that pair while
		keeping unrelated anonymous `{key, value}` objects on `HxAnon`.
	**/
	public function plan(root:TypedExpr):OcamlStructuralFieldPlan {
		tuplePairsByHostLocalId = discoverTuplePairLocals(root);
		final decisions:Array<OcamlStructuralFieldDecision> = [];
		final occurrences:Array<OcamlStructuralFieldOccurrence> = [];

		function record(expression:TypedExpr, decision:Null<OcamlStructuralFieldDecision>):Void {
			if (decision == null)
				return;
			if (anonymousStructures.operationFor(expression, representations) != null)
				return;
			decisions.push(decision);
			occurrences.push({expression: expression, decisionId: decision.id});
		}

		function visit(expression:TypedExpr):Void {
			final currentOrdinal = ordinal++;
			switch (expression.expr) {
				case TCall({expr: TField(receiver, _)}, arguments):
					final call = calls.decisionFor(expression);
					if (call != null && call.kind == OcamlCallKind.StructuralIteratorMethod) {
						visit(receiver);
						for (argument in arguments)
							visit(argument);
					} else {
						TypedExprTools.iter(expression, visit);
					}
				case TBinop(OpAssign, {expr: TField(receiver, FAnon(fieldRef))}, value):
					record(expression, selectWrite(expression, receiver, fieldRef.get(), currentOrdinal));
					visit(receiver);
					visit(value);
				case TField(receiver, FAnon(fieldRef)):
					record(expression, selectRead(expression, receiver, fieldRef.get(), currentOrdinal, true));
					visit(receiver);
				case TField(receiver, FClosure(null, fieldRef)):
					record(expression, selectRead(expression, receiver, fieldRef.get(), currentOrdinal, false));
					visit(receiver);
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}

		visit(root);
		return new OcamlStructuralFieldPlan(decisions, occurrences);
	}

	/** Returns whether syntax must demand a decision for this expression. */
	public static function isCandidate(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TField(_, FAnon(fieldRef)):
				OcamlStructuralFieldContract.ownsFieldName(fieldRef.get().name);
			case TField(receiver, FClosure(null, fieldRef)):
				OcamlStructuralIteratorCallContract.selectMethodValue(receiver, fieldRef.get()) != null;
			case TBinop(OpAssign, {expr: TField(_, FAnon(fieldRef))}, _):
				OcamlStructuralFieldContract.ownsFieldName(fieldRef.get().name);
			case _:
				false;
		}
	}

	/** Rechecks plain decision facts against their request-local typed occurrence. */
	public static function matches(decision:OcamlStructuralFieldDecision, expression:TypedExpr):Bool {
		return mismatchReason(decision, expression) == null;
	}

	/**
		Explains why a previously typed field decision can no longer be consumed.

		A non-null result means some behavior-bearing typed fact changed between
		planning and code generation. Naming the exact fact keeps this fail-closed
		check useful: a maintainer sees whether the source occurrence, receiver,
		field type, result type, or Iterator classification drifted instead of
		being tempted to remove the check merely to let generation continue.
	**/
	public static function mismatchReason(decision:OcamlStructuralFieldDecision, expression:TypedExpr):Null<String> {
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		if (source.file != decision.source.file || source.min != decision.source.min || source.max != decision.source.max)
			return 'source expected=${decision.source.file}:${decision.source.min}-${decision.source.max} actual=${source.file}:${source.min}-${source.max}';
		return switch (expression.expr) {
			case TField(receiver, FAnon(fieldRef)):
				readMismatch(decision, receiver, fieldRef.get(), expression.t, true);
			case TField(receiver, FClosure(null, fieldRef)):
				readMismatch(decision, receiver, fieldRef.get(), expression.t, false);
			case TBinop(OpAssign, {expr: TField(receiver, FAnon(fieldRef))}, _):
				writeMismatch(decision, receiver, fieldRef.get(), expression.t);
			case _:
				"expression shape is no longer an owned structural field read, method capture, or write";
		}
	}

	function selectRead(expression:TypedExpr, receiver:TypedExpr, field:ClassField, occurrenceOrdinal:Int,
			storedFieldAllowed:Bool):Null<OcamlStructuralFieldDecision> {
		if (!OcamlStructuralFieldContract.ownsFieldName(field.name))
			return null;
		final iteratorTarget = OcamlStructuralIteratorCallContract.selectMethodValue(receiver, field);
		if (iteratorTarget == null && !storedFieldAllowed)
			return null;
		final fieldSemanticTypeId = TypeTools.toString(field.type);
		final tupleTarget = iteratorTarget == null ? tupleProjectionTarget(receiver, field.name) : null;
		final operation = iteratorTarget != null ? CaptureIteratorMethod : tupleTarget == null ? ReadStoredField : field.name == "key" ? ProjectTupleKey : ProjectTupleValue;
		final decision = baseDecision(expression, receiver, field, occurrenceOrdinal, operation, fieldSemanticTypeId);
		if (tupleTarget != null) {
			decision.receiverCarrierTypeId = 'tuple<${tupleTarget.keySemanticTypeId},${tupleTarget.valueSemanticTypeId}>';
			decision.runtimeModule = "Stdlib";
			decision.runtimeOperation = tupleTarget.projection;
			decision.evaluationSchedule = ["materialize-receiver", "project-field"];
			decision.keyValueTupleTarget = tupleTarget;
			decision.proofId = OcamlStructuralFieldContract.KEY_VALUE_TUPLE_PROOF_ID;
			decision.proofClaim = OcamlStructuralFieldContract.KEY_VALUE_TUPLE_PROOF_CLAIM;
		} else if (iteratorTarget == null) {
			decision.receiverCarrierTypeId = "Obj.t";
			decision.loadConversion = fieldSemanticTypeId == "Bool" ? UnboxBool : ObjObj;
			decision.runtimeModule = "HxAnon";
			decision.runtimeOperation = "get";
			decision.evaluationSchedule = ["materialize-receiver", "read-field"];
			decision.proofId = OcamlStructuralFieldContract.STORED_PROOF_ID;
			decision.proofClaim = OcamlStructuralFieldContract.STORED_PROOF_CLAIM;
		} else {
			decision.receiverCarrierTypeId = iteratorTarget.receiverCarrierTypeId;
			decision.runtimeModule = iteratorTarget.runtimeModule;
			decision.runtimeOperation = iteratorTarget.runtimeFunction;
			decision.evaluationSchedule = ["materialize-receiver", "capture-method"];
			decision.iteratorTarget = iteratorTarget;
			decision.proofId = OcamlStructuralFieldContract.ITERATOR_PROOF_ID;
			decision.proofClaim = OcamlStructuralFieldContract.ITERATOR_PROOF_CLAIM;
		}
		return finalize(decision);
	}

	function selectWrite(expression:TypedExpr, receiver:TypedExpr, field:ClassField, occurrenceOrdinal:Int):Null<OcamlStructuralFieldDecision> {
		if (!OcamlStructuralFieldContract.ownsFieldName(field.name))
			return null;
		if (tupleProjectionTarget(receiver, field.name) != null)
			throw 'reflaxe.ocaml [ocaml-structural-field:unsupported-tuple-write]: the ${field.name} field belongs to an immutable pair produced by Map.keyValueIterator(); assign to an ordinary object field or construct a new pair instead';
		final fieldSemanticTypeId = TypeTools.toString(field.type);
		final decision = baseDecision(expression, receiver, field, occurrenceOrdinal, WriteStoredField, fieldSemanticTypeId);
		decision.receiverCarrierTypeId = "Obj.t";
		decision.storeConversion = fieldSemanticTypeId == "Bool" ? BoxBool : ObjRepr;
		decision.runtimeModule = "HxAnon";
		decision.runtimeOperation = "set";
		decision.evaluationSchedule = ["materialize-receiver", "materialize-value", "write-field"];
		decision.proofId = OcamlStructuralFieldContract.STORED_PROOF_ID;
		decision.proofClaim = OcamlStructuralFieldContract.STORED_PROOF_CLAIM;
		return finalize(decision);
	}

	function baseDecision(expression:TypedExpr, receiver:TypedExpr, field:ClassField, occurrenceOrdinal:Int, operation:OcamlStructuralFieldOperation,
			resultSemanticTypeId:String):Dynamic {
		return {
			id: "",
			occurrenceOrdinal: occurrenceOrdinal,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			operation: operation,
			fieldName: field.name,
			receiverSemanticTypeId: TypeTools.toString(receiver.t),
			receiverCarrierTypeId: "",
			fieldSemanticTypeId: TypeTools.toString(field.type),
			resultSemanticTypeId: resultSemanticTypeId,
			loadConversion: null,
			storeConversion: null,
			runtimeModule: "",
			runtimeOperation: "",
			runtimeRequirementIds: [],
			runtimeUseOccurrences: [],
			evaluationSchedule: [],
			iteratorTarget: null,
			keyValueTupleTarget: null,
			proofId: "",
			proofClaim: "",
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	function finalize(raw:Dynamic):OcamlStructuralFieldDecision {
		final provisional:OcamlStructuralFieldDecision = cast raw;
		final id = OcamlStructuralFieldContract.decisionId(provisional);
		Reflect.setField(raw, "id", id);
		final identified:OcamlStructuralFieldDecision = cast raw;
		Reflect.setField(raw, "runtimeRequirementIds", OcamlStructuralFieldContract.runtimeRequirementIdsFor(identified));
		Reflect.setField(raw, "runtimeUseOccurrences", OcamlStructuralFieldContract.runtimeUseOccurrencesFor(identified));
		final decision:OcamlStructuralFieldDecision = cast raw;
		OcamlStructuralFieldContract.require(decision);
		return decision;
	}

	/**
		Finds pair locals whose tuple representation is proven by existing calls.

		The target intentionally accepts only direct compiler-typed local
		initializers. It does not follow aliases, assignments, field names, or
		anonymous-object shape. A future broader data-flow model must extend this
		proof explicitly rather than making the syntax renderer guess.
	**/
	function discoverTuplePairLocals(root:TypedExpr):Map<Int, OcamlTuplePairLocalProof> {
		final initializers:Array<OcamlLocalInitializer> = [];
		final reassigned:Map<Int, Bool> = [];

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, initializer) if (initializer != null):
					initializers.push({
						hostLocalId: local.id,
						semanticTypeId: TypeTools.toString(local.t),
						resolvedSemanticTypeId: resolvedSemanticTypeId(local.t),
						expression: initializer
					});
					TypedExprTools.iter(initializer, visit);
				case TBinop(OpAssign, {expr: TLocal(local)}, value):
					reassigned.set(local.id, true);
					visit(value);
				case TBinop(OpAssignOp(_), {expr: TLocal(local)}, value):
					reassigned.set(local.id, true);
					visit(value);
				case TUnop(OpIncrement | OpDecrement, _, {expr: TLocal(local)}):
					reassigned.set(local.id, true);
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}

		visit(root);
		final iterators:Map<Int, OcamlTupleIteratorLocalProof> = [];
		for (initializer in initializers) {
			if (reassigned.exists(initializer.hostLocalId))
				continue;
			final expression = transparentExpression(initializer.expression);
			final interfaceCall = iMapInterfaces.callFor(expression);
			final call = calls.decisionFor(expression);
			final target = call == null ? null : call.standardIMapTarget;
			var proof:Null<OcamlTupleIteratorLocalProof> = null;
			if (interfaceCall != null
				&& interfaceCall.operation == OcamlStandardIMapOperation.Pairs
				&& interfaceCall.resultSemanticTypeId == initializer.semanticTypeId) {
				proof = {
					producerKind: "imap-interface-call",
					producerId: interfaceCall.id,
					producerSourceId: "haxe.Constraints.IMap.keyValueIterator",
					iteratorLocalId: localIdentities.requireHostId(initializer.hostLocalId).id,
					iteratorSemanticTypeId: interfaceCall.resultSemanticTypeId,
					keySemanticTypeId: interfaceCall.keySemanticTypeId,
					valueSemanticTypeId: interfaceCall.valueSemanticTypeId
				};
			} else if (call != null
				&& call.kind == OcamlCallKind.StandardIMapMethod
				&& target != null
				&& target.operation == OcamlStandardIMapOperation.Pairs
				&& target.resultSemanticTypeId == initializer.semanticTypeId) {
				proof = {
					producerKind: "standard-imap-call",
					producerId: call.id,
					producerSourceId: "haxe.Constraints.IMap.keyValueIterator",
					iteratorLocalId: localIdentities.requireHostId(initializer.hostLocalId).id,
					iteratorSemanticTypeId: target.resultSemanticTypeId,
					keySemanticTypeId: target.keySemanticTypeId,
					valueSemanticTypeId: target.valueSemanticTypeId
				};
			} else {
				final targetNative = OcamlStandardMapCarrierContract.pairProducerForExpression(expression);
				if (targetNative != null && initializer.resolvedSemanticTypeId == resolvedSemanticTypeId(expression.t))
					proof = {
						producerKind: "target-native-standard-map-call",
						producerId: targetNative.proofId,
						producerSourceId: targetNative.sourceDeclarationId,
						iteratorLocalId: localIdentities.requireHostId(initializer.hostLocalId).id,
						iteratorSemanticTypeId: initializer.semanticTypeId,
						keySemanticTypeId: targetNative.keySemanticTypeId,
						valueSemanticTypeId: targetNative.valueSemanticTypeId
					};
			}
			if (proof == null)
				continue;
			iterators.set(initializer.hostLocalId, proof);
		}

		final pairs:Map<Int, OcamlTuplePairLocalProof> = [];
		for (initializer in initializers) {
			if (reassigned.exists(initializer.hostLocalId))
				continue;
			final expression = transparentExpression(initializer.expression);
			final call = calls.decisionFor(expression);
			final target = call == null ? null : call.structuralIteratorTarget;
			if (call == null
				|| call.kind != OcamlCallKind.StructuralIteratorMethod
				|| target == null
				|| target.operation != OcamlStructuralIteratorOperation.Next
				|| target.resultSemanticTypeId != initializer.semanticTypeId)
				continue;
			final receiverHostId = structuralCallReceiverLocalId(expression);
			final iterator = receiverHostId == null ? null : iterators.get(receiverHostId);
			if (iterator == null || target.receiverSemanticTypeId != iterator.iteratorSemanticTypeId)
				continue;
			pairs.set(initializer.hostLocalId, {
				iterator: iterator,
				pairProducerCallId: call.id,
				pairLocalId: localIdentities.requireHostId(initializer.hostLocalId).id,
				pairSemanticTypeId: initializer.semanticTypeId
			});
		}
		return pairs;
	}

	/** Returns the tuple proof only for a `key` or `value` read on its exact pair local. */
	function tupleProjectionTarget(receiver:TypedExpr, fieldName:String):Null<OcamlKeyValueTupleProjectionTarget> {
		if (fieldName != "key" && fieldName != "value")
			return null;
		final hostLocalId = localExpressionId(receiver);
		final pair = hostLocalId == null ? null : tuplePairsByHostLocalId.get(hostLocalId);
		if (pair == null || TypeTools.toString(receiver.t) != pair.pairSemanticTypeId)
			return null;
		return {
			projection: fieldName == "key" ? "fst" : "snd",
			iteratorProducerKind: pair.iterator.producerKind,
			iteratorProducerId: pair.iterator.producerId,
			iteratorProducerSourceId: pair.iterator.producerSourceId,
			pairProducerCallId: pair.pairProducerCallId,
			iteratorLocalId: pair.iterator.iteratorLocalId,
			pairLocalId: pair.pairLocalId,
			iteratorSemanticTypeId: pair.iterator.iteratorSemanticTypeId,
			pairSemanticTypeId: pair.pairSemanticTypeId,
			keySemanticTypeId: pair.iterator.keySemanticTypeId,
			valueSemanticTypeId: pair.iterator.valueSemanticTypeId,
			proofId: OcamlStructuralFieldContract.KEY_VALUE_TUPLE_PROOF_ID,
			proofClaim: OcamlStructuralFieldContract.KEY_VALUE_TUPLE_PROOF_CLAIM
		};
	}

	static function transparentExpression(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, inner): transparentExpression(inner);
			case TCast(inner, null): transparentExpression(inner);
			case _: expression;
		}
	}

	/**
		Checks whether a local typedef and its inlined initializer describe one
		resolved structural type without mutating compiler unification state.

		`Map.keyValueIterator()` keeps the public `KeyValueIterator<K,V>` typedef on
		the local, while its exact native helper has the equivalent `Iterator<{key,
		value}>` type. The producer proof retains the public local type so the later
		`next()` receiver can match it exactly.
	**/
	static function resolvedSemanticTypeId(type:Type):String {
		return TypeTools.toString(TypeTools.follow(type));
	}

	static function localExpressionId(expression:TypedExpr):Null<Int> {
		return switch (transparentExpression(expression).expr) {
			case TLocal(local): local.id;
			case _: null;
		}
	}

	static function structuralCallReceiverLocalId(expression:TypedExpr):Null<Int> {
		return switch (transparentExpression(expression).expr) {
			case TCall({expr: TField(receiver, FAnon(_))}, []): localExpressionId(receiver);
			case _: null;
		}
	}

	static function readMismatch(decision:OcamlStructuralFieldDecision, receiver:TypedExpr, field:ClassField, resultType:Type,
			storedFieldAllowed:Bool):Null<String> {
		if (decision.operation == WriteStoredField)
			return "operation changed from a write to a read";
		if (decision.fieldName != field.name)
			return 'field name expected=${decision.fieldName} actual=${field.name}';
		final receiverType = TypeTools.toString(receiver.t);
		if (decision.receiverSemanticTypeId != receiverType)
			return 'receiver type expected=${decision.receiverSemanticTypeId} actual=$receiverType';
		final fieldType = TypeTools.toString(field.type);
		if (decision.fieldSemanticTypeId != fieldType)
			return 'field type expected=${decision.fieldSemanticTypeId} actual=$fieldType';
		final actualResultType = TypeTools.toString(resultType);
		if (decision.resultSemanticTypeId != actualResultType)
			return 'result type expected=${decision.resultSemanticTypeId} actual=$actualResultType';
		final iteratorTarget = OcamlStructuralIteratorCallContract.selectMethodValue(receiver, field);
		if (decision.operation == CaptureIteratorMethod) {
			if (iteratorTarget == null || decision.iteratorTarget == null)
				return "Iterator method ownership is no longer present";
			if (OcamlStructuralIteratorCallContract.fingerprint(iteratorTarget) != OcamlStructuralIteratorCallContract.fingerprint(decision.iteratorTarget))
				return "Iterator method target facts changed";
			return null;
		}
		if (!storedFieldAllowed)
			return "the final field shape no longer permits a stored anonymous field";
		return iteratorTarget == null ? null : "the stored field is now classified as an Iterator method";
	}

	static function writeMismatch(decision:OcamlStructuralFieldDecision, receiver:TypedExpr, field:ClassField, resultType:Type):Null<String> {
		if (decision.operation != WriteStoredField)
			return "operation changed from a read or method capture to a write";
		if (decision.fieldName != field.name)
			return 'field name expected=${decision.fieldName} actual=${field.name}';
		final receiverType = TypeTools.toString(receiver.t);
		if (decision.receiverSemanticTypeId != receiverType)
			return 'receiver type expected=${decision.receiverSemanticTypeId} actual=$receiverType';
		final fieldType = TypeTools.toString(field.type);
		if (decision.fieldSemanticTypeId != fieldType)
			return 'field type expected=${decision.fieldSemanticTypeId} actual=$fieldType';
		final actualResultType = TypeTools.toString(resultType);
		return decision.resultSemanticTypeId == actualResultType ? null : 'result type expected=${decision.resultSemanticTypeId} actual=$actualResultType';
	}
}
#end

#end
