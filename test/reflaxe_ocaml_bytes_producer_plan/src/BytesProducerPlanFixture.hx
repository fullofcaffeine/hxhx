package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesEncodingKind;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerContract;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerKind;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan.OcamlBytesProducerPlanner;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedStandaloneExpressionPlan;
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
		final cases = caseFields();
		final expected = [
			"alloc" => {
				kind: OcamlBytesProducerKind.Alloc,
				encoding: OcamlBytesEncodingKind.NotApplicable,
				argumentCount: 1
			},
			"ofStringDefault" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.Omitted,
				argumentCount: 1
			},
			"ofStringExplicitNull" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.ExplicitNull,
				argumentCount: 2
			},
			"ofStringUtf8" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.UTF8,
				argumentCount: 2
			},
			"ofStringRawNative" => {
				kind: OcamlBytesProducerKind.OfString,
				encoding: OcamlBytesEncodingKind.RawNative,
				argumentCount: 2
			},
			"ofData" => {
				kind: OcamlBytesProducerKind.OfData,
				encoding: OcamlBytesEncodingKind.NotApplicable,
				argumentCount: 1
			},
			"ofHex" => {
				kind: OcamlBytesProducerKind.OfHex,
				encoding: OcamlBytesEncodingKind.NotApplicable,
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
			final first = new OcamlBytesProducerPlanner(binding).plan(body);
			final second = new OcamlBytesProducerPlanner(binding).plan(body);
			if (first.revision != second.revision)
				Context.error('Bytes producer case "$name" has a non-deterministic plan revision.', field.pos);
			final decisions = first.decisions();
			if (decisions.length != 1)
				Context.error('Bytes producer case "$name" expected one decision, received ${decisions.length}.', field.pos);
			final decision = decisions[0];
			if (decision.kind != contract.kind
				|| decision.encoding != contract.encoding
				|| decision.argumentCount != contract.argumentCount
				|| decision.resultSemanticTypeId != OcamlBytesProducerContract.SEMANTIC_TYPE_ID
				|| decision.resultCarrierTypeId != OcamlBytesProducerContract.CARRIER_TYPE_ID
				|| decision.resultNullability != OcamlBytesProducerContract.RESULT_NULLABILITY
				|| decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				Context.error('Bytes producer case "$name" disagrees with its typed producer contract.', field.pos);
			}
			final occurrence = producerOccurrence(body);
			if (occurrence == null)
				Context.error('Bytes producer case "$name" has no admitted occurrence.', field.pos);
			if (first.requireFor(occurrence).id != decision.id)
				Context.error('Bytes producer case "$name" did not resolve its exact sealed occurrence.', field.pos);
			allDecisions.push(decision);
		}

		final unadmittedBody = cases.get("unadmittedInternalConstructor").expr();
		final constructorOccurrence = firstConstructor(unadmittedBody);
		if (constructorOccurrence == null)
			Context.error("The unadmitted constructor fixture has no typed constructor occurrence.", Context.currentPos());
		if (OcamlBytesProducerPlan.admittedKind(constructorOccurrence) != null
			|| new OcamlBytesProducerPlanner(binding("unadmittedInternalConstructor")).plan(unadmittedBody).decisions().length != 0) {
			Context.error("The internal Bytes constructor must remain outside the producer plan until both length and data are represented.",
				constructorOccurrence.pos);
		}

		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(PROGRAM_REVISION);
		for (decision in allDecisions)
			ledger.recordBytesProducer(decision);
		final requirements = ledger.requirementsSorted();
		if (requirements.length != allDecisions.length)
			Context.error('Expected ${allDecisions.length} Bytes requirements, received ${requirements.length}.', Context.currentPos());
		for (requirement in requirements) {
			if (requirement.semanticCapability != OcamlRuntimeRequirementLedger.HAXE_BYTES_PRODUCER
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
		expectThrows("invalid-producer", () -> ledger.recordBytesProducer(copy(sample, {calleeId: sample.calleeId + ":tampered"})));
		expectThrows("stale-producer", () -> new OcamlBytesProducerPlan([sample]).requirePlanBinding({
			functionId: sample.functionId,
			programRevision: sample.programRevision,
			bodyRevision: sample.bodyRevision + ":changed",
			pipelineRevision: sample.pipelineRevision
		}));
		final sampleBody = cases.get("alloc").expr();
		final sampleOccurrence = producerOccurrence(sampleBody);
		expectThrows("missing-producer", () -> new OcamlBytesProducerPlan([]).requireFor(sampleOccurrence));

		final standaloneRegistry = new OcamlFunctionPlanRegistry();
		standaloneRegistry.beginProgram(PROGRAM_REVISION);
		final standaloneOwner = "field-initializer:static:BytesProducerCases::sample";
		final firstStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, sampleBody);
		final secondStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, sampleBody);
		if (firstStandalone.binding.functionId != "standalone:" + standaloneOwner
			|| firstStandalone.binding.bodyRevision != secondStandalone.binding.bodyRevision
			|| firstStandalone.bytesProducers.revision != secondStandalone.bytesProducers.revision
			|| standaloneRegistry.requireStandaloneExpressionPlan(sampleBody, firstStandalone).decisions().length != 1) {
			Context.error("Standalone Bytes planning did not preserve the exact deterministic expression binding.", Context.currentPos());
		}
		final staleStandalone:OcamlSealedStandaloneExpressionPlan = {
			binding: {
				functionId: firstStandalone.binding.functionId,
				programRevision: firstStandalone.binding.programRevision,
				bodyRevision: firstStandalone.binding.bodyRevision + ":changed",
				pipelineRevision: firstStandalone.binding.pipelineRevision
			},
			bytesProducers: firstStandalone.bytesProducers
		};
		expectThrows("stale-standalone-plan", () -> standaloneRegistry.requireStandaloneExpressionPlan(sampleBody, staleStandalone));

		Sys.println("REFLAXE_OCAML_BYTES_PRODUCER_PLAN_FIXTURE:PASS");
		return macro null;
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

	static function firstConstructor(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			switch (expression.expr) {
				case TNew(classRef, _, _) if (OcamlBytesProducerPlan.isBytesClass(classRef.get())):
					found = expression;
				case _:
					TypedExprTools.iter(expression, visit);
			}
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
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultNullability: decision.resultNullability,
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
