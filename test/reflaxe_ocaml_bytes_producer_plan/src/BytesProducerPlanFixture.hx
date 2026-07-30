package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesEncodingKind;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesConstructionPolicy;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerContract;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerKind;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan.OcamlBytesProducerPlanner;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedStandaloneExpressionPlan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationValueMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.runtimegen.OcamlBytesRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

/**
	Checks the revision-bound contract for supported non-null Bytes producers.

	The fixture reads real Haxe 4.3.7 typed expressions, checks every admitted
	producer and encoding form, and deliberately corrupts records so stale,
	duplicate, wrong-kind, wrong-arity, and missing evidence fail before syntax.
**/
class BytesProducerPlanFixture {
	static inline final PROGRAM_REVISION = "program:bytes-producer-fixture";
	static inline final BODY_REVISION = "body:bytes-producer-fixture";
	static inline final PIPELINE_REVISION = "pipeline:bytes-producer-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(PROGRAM_REVISION);
		verifyRepresentationOracleAndContract(representations);
		final cases = caseFields();
		final expected = [
			"internalConstructor" => {
				kind: OcamlBytesProducerKind.Constructor,
				encoding: OcamlBytesEncodingKind.NotApplicable,
				constructionPolicy: OcamlBytesConstructionPolicy.ExplicitLengthAliasedData,
				argumentCount: 2
			},
			"alloc" => {
				kind: OcamlBytesProducerKind.Alloc,
				encoding: OcamlBytesEncodingKind.NotApplicable,
				constructionPolicy: OcamlBytesConstructionPolicy.DerivedLengthOwnedData,
				argumentCount: 1
			},
			"ofStringDefault" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.Omitted,
				constructionPolicy: OcamlBytesConstructionPolicy.DerivedLengthOwnedData,
				argumentCount: 1
			},
			"ofStringExplicitNull" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.ExplicitNull,
				constructionPolicy: OcamlBytesConstructionPolicy.DerivedLengthOwnedData,
				argumentCount: 2
			},
			"ofStringUtf8" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.UTF8,
				constructionPolicy: OcamlBytesConstructionPolicy.DerivedLengthOwnedData,
				argumentCount: 2
			},
			"ofStringRawNative" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.RawNative,
				constructionPolicy: OcamlBytesConstructionPolicy.DerivedLengthOwnedData,
				argumentCount: 2
			},
			"ofData" => {
				kind: OcamlBytesProducerKind.OfData,
				encoding: OcamlBytesEncodingKind.NotApplicable,
				constructionPolicy: OcamlBytesConstructionPolicy.DerivedLengthAliasedData,
				argumentCount: 1
			},
			"ofHex" => {
				kind: OcamlBytesProducerKind.OfHex,
				encoding: OcamlBytesEncodingKind.NotApplicable,
				constructionPolicy: OcamlBytesConstructionPolicy.DerivedLengthOwnedData,
				argumentCount: 1
			}
		];

		final allDecisions:Array<OcamlBytesProducerDecision> = [];
		for (name => contract in expected) {
			final field = cases.get(name);
			if (field == null)
				Context.error('Missing typed Bytes producer case "$name".', Context.currentPos());
			final body = field.expr();
			if (body == null)
				Context.error('Bytes producer case "$name" has no typed body.', field.pos);
			final binding = binding(name);
			final first = new OcamlBytesProducerPlanner(binding, representations).plan(body);
			final second = new OcamlBytesProducerPlanner(binding, representations).plan(body);
			if (first.revision != second.revision)
				Context.error('Bytes producer case "$name" has a non-deterministic plan revision.', field.pos);
			final decisions = first.decisions();
			if (decisions.length != 1)
				Context.error('Bytes producer case "$name" expected one decision, received ${decisions.length}.', field.pos);
			final decision = decisions[0];
			if (decision.kind != contract.kind
				|| decision.encoding != contract.encoding
				|| decision.constructionPolicy != contract.constructionPolicy
				|| decision.argumentCount != contract.argumentCount
				|| decision.resultSemanticTypeId != OcamlBytesProducerContract.SEMANTIC_TYPE_ID
				|| decision.resultCarrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
				|| decision.resultNullability != OcamlBytesProducerContract.RESULT_NULLABILITY
				|| decision.resultRepresentationId != OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
				|| decision.resultRepresentationRevision != representations.requireExactBytesInternal(decision.resultRepresentationId,
					decision.resultRepresentationRevision, decision.programRevision)
					.revision || decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				Context.error('Bytes producer case "$name" disagrees with its typed producer contract.', field.pos);
			}
			final occurrence = producerOccurrence(body);
			if (occurrence == null)
				Context.error('Bytes producer case "$name" has no admitted occurrence.', field.pos);
			if (first.requireFor(occurrence, representations).id != decision.id)
				Context.error('Bytes producer case "$name" did not resolve its exact sealed occurrence.', field.pos);
			allDecisions.push(decision);
		}

		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(PROGRAM_REVISION);
		for (decision in allDecisions)
			OcamlBytesRuntimeRequirementRecorder.recordProducer(ledger, decision);
		final requirements = ledger.requirementsSorted();
		if (requirements.length != allDecisions.length)
			Context.error('Expected ${allDecisions.length} Bytes requirements, received ${requirements.length}.', Context.currentPos());
		for (requirement in requirements) {
			if (requirement.semanticCapability != OcamlBytesRuntimeRequirementRecorder.HAXE_BYTES_PRODUCER
				|| requirement.subject.id != OcamlBytesProducerContract.SEMANTIC_TYPE_ID
				|| requirement.rootModules.length != 1
				|| requirement.rootModules[0] != "HxBytes") {
				Context.error('Runtime requirement "${requirement.id}" does not select the exact HxBytes producer contract.', Context.currentPos());
			}
		}

		final sample = allDecisions[0];
		expectThrows("duplicate-producer", () -> new OcamlBytesProducerPlan([sample, sample]));
		expectThrows("invalid-producer", () -> new OcamlBytesProducerPlan([copy(sample, {kind: OcamlBytesProducerKind.Alloc})]));
		expectThrows("invalid-producer", () -> new OcamlBytesProducerPlan([copy(sample, {argumentCount: 1})]));
		expectThrows("invalid-producer", () -> new OcamlBytesProducerPlan([copy(sample, {constructionPolicy: cast "invalid-policy"})]));
		expectThrows("invalid-producer",
			() -> OcamlBytesRuntimeRequirementRecorder.recordProducer(ledger, copy(sample, {calleeId: sample.calleeId + ":tampered"})));
		expectThrows("stale-producer", () -> new OcamlBytesProducerPlan([sample]).requirePlanBinding({
			functionId: sample.functionId,
			programRevision: sample.programRevision,
			bodyRevision: sample.bodyRevision + ":changed",
			pipelineRevision: sample.pipelineRevision
		}));
		final sampleBody = cases.get("alloc").expr();
		final sampleOccurrence = producerOccurrence(sampleBody);
		final allocDecision = Lambda.find(allDecisions, decision -> decision.kind == OcamlBytesProducerKind.Alloc);
		if (allocDecision == null)
			Context.error("The Bytes producer fixture has no alloc decision.", Context.currentPos());
		expectThrows("missing-producer", () -> new OcamlBytesProducerPlan([]).requireFor(sampleOccurrence, representations));
		final missingRepresentations = new OcamlRepresentationRegistry();
		missingRepresentations.beginProgram(PROGRAM_REVISION);
		expectThrows("missing-decision", () -> new OcamlBytesProducerPlan([allocDecision]).requireFor(sampleOccurrence, missingRepresentations));
		expectThrows("invalid-producer", () -> new OcamlBytesProducerPlan([
			copy(sample, {resultRepresentationId: "representation:Null<haxe.io.Bytes>:internal-value"})
		]));
		expectThrows("invalid-producer", () -> new OcamlBytesProducerPlan([copy(sample, {resultCarrierTypeId: "Obj.t"})]));

		final standaloneRegistry = new OcamlFunctionPlanRegistry();
		standaloneRegistry.beginProgram(PROGRAM_REVISION);
		final standaloneOwner = "field-initializer:static:BytesProducerCases::sample";
		final firstStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, sampleBody, representations);
		final secondStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, sampleBody, representations);
		if (firstStandalone.binding.functionId != "standalone:" + standaloneOwner
			|| firstStandalone.binding.bodyRevision != secondStandalone.binding.bodyRevision
			|| firstStandalone.bytesProducers.revision != secondStandalone.bytesProducers.revision
			|| standaloneRegistry.requireStandaloneExpressionPlan(sampleBody, firstStandalone, representations).bytesProducers.decisions().length != 1) {
			Context.error("Standalone Bytes planning did not preserve the exact deterministic expression binding.", Context.currentPos());
		}
		final staleStandalone:OcamlSealedStandaloneExpressionPlan = {
			binding: {
				functionId: firstStandalone.binding.functionId,
				programRevision: firstStandalone.binding.programRevision,
				bodyRevision: firstStandalone.binding.bodyRevision + ":changed",
				pipelineRevision: firstStandalone.binding.pipelineRevision
			},
			anonymousStructures: firstStandalone.anonymousStructures,
			bytesAccesses: firstStandalone.bytesAccesses,
			bytesMutations: firstStandalone.bytesMutations,
			bytesProducers: firstStandalone.bytesProducers,
			bytesReads: firstStandalone.bytesReads
		};
		expectThrows("stale-standalone-plan", () -> standaloneRegistry.requireStandaloneExpressionPlan(sampleBody, staleStandalone, representations));

		Sys.println("REFLAXE_OCAML_BYTES_PRODUCER_PLAN_FIXTURE:PASS");
		return macro null;
	}

	static function verifyRepresentationOracleAndContract(representations:OcamlRepresentationRegistry):Void {
		final directType = Context.typeof(macro(null : haxe.io.Bytes));
		final explicitNullType = Context.typeof(macro(null : Null<haxe.io.Bytes>));
		final producerType = Context.typeof(macro haxe.io.Bytes.alloc(1));
		final aliasType = Context.typeof(macro(null : BytesProducerCases.BytesAlias));
		final wrapperType = Context.typeof(macro(null : BytesProducerCases.BytesWrapper));
		if (!OcamlRepresentationRegistry.isExactBytes(directType)
			|| OcamlRepresentationRegistry.isExactNullBytes(directType)
			|| !OcamlRepresentationRegistry.isExactNullBytes(explicitNullType)
			|| OcamlRepresentationRegistry.isExactBytes(explicitNullType)
			|| !OcamlRepresentationRegistry.isExactBytes(producerType)
			|| OcamlRepresentationRegistry.isExactBytes(aliasType)
			|| OcamlRepresentationRegistry.isExactNullBytes(aliasType)
			|| OcamlRepresentationRegistry.isExactBytes(wrapperType)
			|| OcamlRepresentationRegistry.isExactNullBytes(wrapperType)
			|| OcamlRepresentationRegistry.isExactBytes(Context.typeof(macro(null : Dynamic)))
			|| OcamlRepresentationRegistry.isExactBytes(Context.typeof(macro(null : String)))) {
			Context.error("Haxe 4.3.7 Bytes and Null<Bytes> typed forms do not match the exact representation classifiers.", Context.currentPos());
		}

		final direct = representations.selectExactBytes(OcamlRepresentationDomain.InternalValue);
		final explicitNull = representations.selectExactNullBytes(OcamlRepresentationDomain.InternalValue);
		for (decision in [direct, explicitNull]) {
			if (decision.carrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
				|| OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID != "bytes"
				|| OcamlBytesRepresentationContract.CARRIER_SHAPE_ID != "explicit-length+mutable-native-data-v1"
				|| OcamlBytesRepresentationContract.DATA_ALIASING_POLICY != "shared-native-data-alias"
				|| OcamlBytesRepresentationContract.RANGE_BOUNDS_POLICY != "declared-length"
				|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
				|| decision.identityPolicy != OcamlRepresentationIdentityPolicy.ReferenceIdentity
				|| decision.aliasingPolicy != OcamlRepresentationAliasingPolicy.SharedReferenceAliases
				|| decision.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
				|| decision.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer
				|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectRuntimeContainer
				|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted) {
				Context.error('Bytes representation "${decision.id}" does not preserve the nullable shared-reference carrier contract.', Context.currentPos());
			}
		}
		if (direct.semanticTypeId != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			|| explicitNull.semanticTypeId != OcamlBytesRepresentationContract.EXPLICIT_NULL_SEMANTIC_TYPE_ID
			|| direct.id == explicitNull.id
			|| direct.revision == explicitNull.revision) {
			Context.error("Direct Bytes and explicit Null<Bytes> lost their distinct semantic representation identities.", Context.currentPos());
		}
		representations.requireExactBytesInternal(direct.id, direct.revision, PROGRAM_REVISION);
		expectThrows("representation-mismatch",
			() -> representations.requireExactBytesInternal(direct.id, "sha256:" + StringTools.lpad("", "0", 64), PROGRAM_REVISION));
		expectThrows("representation-mismatch", () -> representations.requireExactBytesInternal(explicitNull.id, explicitNull.revision, PROGRAM_REVISION));
		expectThrows("unsupported-bytes-domain", () -> representations.selectExactBytes(OcamlRepresentationDomain.MutableLocalStorage));
		expectThrows("unsupported-bytes-domain", () -> representations.selectExactNullBytes(OcamlRepresentationDomain.StaticField));
	}

	static function binding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "BytesProducerCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: BODY_REVISION + ":" + name,
			pipelineRevision: PIPELINE_REVISION
		};
	}

	static function caseFields():Map<String, ClassField> {
		return switch (Context.getType("BytesProducerCases")) {
			case TInst(classRef, _):
				[for (field in classRef.get().statics.get()) field.name => field];
			case _:
				Context.error("BytesProducerCases did not resolve to a class.", Context.currentPos());
		}
	}

	static function producerOccurrence(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			if (OcamlBytesProducerPlan.admittedKind(expression) != null) {
				found = expression;
				return;
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		return found;
	}

	static function copy(decision:OcamlBytesProducerDecision, changes:Dynamic):OcamlBytesProducerDecision {
		final value:Dynamic = {
			id: decision.id,
			source: decision.source,
			kind: decision.kind,
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			argumentCount: decision.argumentCount,
			argumentEvaluationOrder: decision.argumentEvaluationOrder.copy(),
			encoding: decision.encoding,
			constructionPolicy: decision.constructionPolicy,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultNullability: decision.resultNullability,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		for (field in Reflect.fields(changes))
			Reflect.setField(value, field, Reflect.field(changes, field));
		return cast value;
	}

	static function expectThrows(code:String, operation:Void->Void):Void {
		expectedFailureIndex += 1;
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || message.indexOf(code) < 0)
			Context.error('Expected failure $expectedFailureIndex containing "$code", received ${message == null ? "no failure" : message}.',
				Context.currentPos());
	}
}
