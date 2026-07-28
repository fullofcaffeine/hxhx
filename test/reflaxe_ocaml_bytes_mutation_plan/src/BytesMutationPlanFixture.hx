package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationContract;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationDecision;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationKind;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationOverlapPolicy;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationResultKind;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationSourcePolicy;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationValuePolicy;
import reflaxe.ocaml.lowered.OcamlBytesMutationPlan;
import reflaxe.ocaml.lowered.OcamlBytesMutationPlan.OcamlBytesMutationPlanner;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

/**
	Checks that exact Bytes mutations are deterministic and fail closed.

	The fixture consumes real typed Haxe 4.3.7 declarations, verifies the
	receiver-first schedule and mutation policies, then corrupts individual
	facts to prove no stale or incomplete record can reach OCaml syntax.
**/
class BytesMutationPlanFixture {
	static inline final PROGRAM_REVISION = "program:bytes-mutation-fixture";
	static inline final BODY_REVISION = "body:bytes-mutation-fixture";
	static inline final PIPELINE_REVISION = "pipeline:bytes-mutation-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(PROGRAM_REVISION);
		final cases = caseFields();
		final decisions:Array<OcamlBytesMutationDecision> = [];
		for (name => kind in [
			"fill" => OcamlBytesMutationKind.Fill,
			"fillNullableValue" => OcamlBytesMutationKind.Fill,
			"blit" => OcamlBytesMutationKind.Blit,
			"fillInSourceOrder" => OcamlBytesMutationKind.Fill,
			"blitInSourceOrder" => OcamlBytesMutationKind.Blit
		]) {
			final field = requireField(cases, name);
			final body = requireBody(field);
			final binding = binding(name);
			final first = new OcamlBytesMutationPlanner(binding, representations).plan(body);
			final second = new OcamlBytesMutationPlanner(binding, representations).plan(body);
			if (first.revision != second.revision)
				Context.error('Bytes mutation case "$name" has a non-deterministic plan revision.', field.pos);
			final planned = first.decisions();
			if (planned.length != 1)
				Context.error('Bytes mutation case "$name" expected one decision, received ${planned.length}.', field.pos);
			final decision = planned[0];
			final expectedArgumentCount = kind == OcamlBytesMutationKind.Fill ? 3 : 4;
			final expectedSourcePolicy = kind == OcamlBytesMutationKind.Fill ? OcamlBytesMutationSourcePolicy.NoSource : OcamlBytesMutationSourcePolicy.ReadSourceRange;
			final expectedOverlapPolicy = kind == OcamlBytesMutationKind.Fill ? OcamlBytesMutationOverlapPolicy.NotApplicable : OcamlBytesMutationOverlapPolicy.MemmoveCompatible;
			final expectedValuePolicy = kind == OcamlBytesMutationKind.Fill ? OcamlBytesMutationValuePolicy.MaskLowEightBits : OcamlBytesMutationValuePolicy.ExactByteCopy;
			if (decision.kind != kind
				|| decision.argumentCount != expectedArgumentCount
				|| decision.evaluationOrder.join(",") != [-1].concat([for (index in 0...expectedArgumentCount) index]).join(",")
				|| decision.destinationPolicy != OcamlBytesMutationContract.DESTINATION_POLICY
				|| decision.sourcePolicy != expectedSourcePolicy
				|| decision.overlapPolicy != expectedOverlapPolicy
				|| decision.boundsPolicy != OcamlBytesMutationContract.BOUNDS_POLICY
				|| decision.valuePolicy != expectedValuePolicy
				|| decision.resultKind != OcamlBytesMutationResultKind.EffectOnlyVoid
				|| decision.resultSemanticTypeId != "Void") {
				Context.error('Bytes mutation case "$name" disagrees with its typed mutation contract.', field.pos);
			}
			if (name == "fillNullableValue") {
				if (decision.argumentInputSemanticTypeIds[2] != "Null<Int>"
					|| decision.argumentSemanticTypeIds[2] != "Int"
					|| decision.argumentConversions[2] != OcamlBytesMutationArgumentConversion.RequireNonNullInt) {
					Context.error("Nullable Bytes fill input did not seal its non-null Int boundary crossing.", field.pos);
				}
			} else if (Lambda.exists(decision.argumentConversions, conversion -> conversion != OcamlBytesMutationArgumentConversion.Identity)) {
				Context.error('Exact Bytes mutation case "$name" unexpectedly selected an argument conversion.', field.pos);
			}
			final occurrence = mutationOccurrence(body);
			if (occurrence == null || first.requireFor(occurrence, representations).id != decision.id)
				Context.error('Bytes mutation case "$name" did not resolve its exact sealed occurrence.', field.pos);
			decisions.push(decision);
		}

		final lookalike = requireBody(requireField(cases, "userLookalike"));
		final lookalikePlan = new OcamlBytesMutationPlanner(binding("userLookalike"), representations).plan(lookalike);
		if (lookalikePlan.decisions().length != 0)
			Context.error("User-defined fill/blit lookalikes were admitted as haxe.io.Bytes mutations.", Context.currentPos());

		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(PROGRAM_REVISION);
		for (decision in decisions)
			ledger.recordBytesMutation(decision);
		final requirements = ledger.requirementsSorted();
		if (requirements.length != decisions.length)
			Context.error('Expected ${decisions.length} Bytes mutation requirements, received ${requirements.length}.', Context.currentPos());
		for (requirement in requirements) {
			if (requirement.semanticCapability != OcamlRuntimeRequirementLedger.HAXE_BYTES_MUTATION
				|| requirement.subject.id != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
				|| requirement.rootModules.join(",") != "HxBytes") {
				Context.error('Runtime requirement "${requirement.id}" does not select the exact HxBytes mutation contract.', Context.currentPos());
			}
		}

		final sample = Lambda.find(decisions, decision -> decision.kind == OcamlBytesMutationKind.Blit
			&& decision.functionId == "BytesMutationCases.blit");
		if (sample == null)
			Context.error("The Bytes mutation fixture has no blit decision.", Context.currentPos());
		expectThrows("duplicate-mutation", () -> new OcamlBytesMutationPlan([sample, sample]));
		expectThrows("conflicting-mutation", () -> new OcamlBytesMutationPlan([sample, reseal(sample, {bodyRevision: sample.bodyRevision + ":conflict"})]));
		expectThrows("invalid-mutation", () -> new OcamlBytesMutationPlan([copy(sample, {kind: OcamlBytesMutationKind.Fill})]));
		expectThrows("invalid-mutation", () -> new OcamlBytesMutationPlan([copy(sample, {evaluationOrder: [-1, 1, 0, 2, 3]})]));
		expectThrows("invalid-mutation-argument", () -> new OcamlBytesMutationPlan([reseal(sample, {argumentCarrierTypeIds: ["int", "int", "int", "int"]})]));
		expectThrows("invalid-mutation-conversion",
			() -> new OcamlBytesMutationPlan([reseal(sample, {argumentInputSemanticTypeIds: ["Int", "Int", "Int", "Int"]})]));
		expectThrows("invalid-mutation", () -> new OcamlBytesMutationPlan([reseal(sample, {overlapPolicy: OcamlBytesMutationOverlapPolicy.NotApplicable})]));
		expectThrows("invalid-mutation", () -> ledger.recordBytesMutation(copy(sample, {calleeId: sample.calleeId + ":tampered"})));
		expectThrows("stale-mutation", () -> new OcamlBytesMutationPlan([sample]).requirePlanBinding({
			functionId: sample.functionId,
			programRevision: sample.programRevision,
			bodyRevision: sample.bodyRevision + ":changed",
			pipelineRevision: sample.pipelineRevision
		}));

		final blitBody = requireBody(requireField(cases, "blit"));
		final blitOccurrence = mutationOccurrence(blitBody);
		expectThrows("missing-mutation", () -> new OcamlBytesMutationPlan([]).requireFor(blitOccurrence, representations));
		final missingRepresentations = new OcamlRepresentationRegistry();
		missingRepresentations.beginProgram(PROGRAM_REVISION);
		expectThrows("missing-decision", () -> new OcamlBytesMutationPlan([sample]).requireFor(blitOccurrence, missingRepresentations));

		final standaloneRegistry = new OcamlFunctionPlanRegistry();
		standaloneRegistry.beginProgram(PROGRAM_REVISION);
		final firstStandalone = standaloneRegistry.sealStandaloneExpression("field-initializer:static:BytesMutationCases::blit", blitBody, representations);
		final secondStandalone = standaloneRegistry.sealStandaloneExpression("field-initializer:static:BytesMutationCases::blit", blitBody, representations);
		standaloneRegistry.requireStandaloneExpressionPlan(blitBody, firstStandalone, representations);
		if (firstStandalone.bytesMutations.revision != secondStandalone.bytesMutations.revision
			|| firstStandalone.bytesMutations.decisions().length != 1) {
			Context.error("Standalone Bytes mutation planning did not preserve the exact deterministic expression binding.", Context.currentPos());
		}

		Sys.println("REFLAXE_OCAML_BYTES_MUTATION_PLAN_FIXTURE:PASS");
		return macro null;
	}

	static function binding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "BytesMutationCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: BODY_REVISION + ":" + name,
			pipelineRevision: PIPELINE_REVISION
		};
	}

	static function caseFields():Map<String, ClassField> {
		return switch (Context.getType("BytesMutationCases")) {
			case TInst(classRef, _): [for (field in classRef.get().statics.get()) field.name => field];
			case _: Context.error("BytesMutationCases did not resolve to a class.", Context.currentPos());
		}
	}

	static function requireField(fields:Map<String, ClassField>, name:String):ClassField {
		final field = fields.get(name);
		if (field == null)
			Context.error('Missing typed Bytes mutation case "$name".', Context.currentPos());
		return field;
	}

	static function requireBody(field:ClassField):TypedExpr {
		final body = field.expr();
		if (body == null)
			Context.error('Bytes mutation case "${field.name}" has no typed body.', field.pos);
		return body;
	}

	static function mutationOccurrence(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			if (OcamlBytesMutationPlan.admittedOccurrence(expression) != null) {
				found = expression;
				return;
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		return found;
	}

	static function copy(decision:OcamlBytesMutationDecision, changes:Dynamic):OcamlBytesMutationDecision {
		final value:Dynamic = {};
		for (field in Reflect.fields(decision))
			Reflect.setField(value, field, Reflect.field(decision, field));
		for (field in Reflect.fields(changes))
			Reflect.setField(value, field, Reflect.field(changes, field));
		return cast value;
	}

	static function reseal(decision:OcamlBytesMutationDecision, changes:Dynamic):OcamlBytesMutationDecision {
		final value:Dynamic = copy(decision, changes);
		final changed:OcamlBytesMutationDecision = cast value;
		final id = OcamlBytesMutationContract.idFor(changed);
		Reflect.setField(value, "id", id);
		Reflect.setField(value, "runtimeRequirementIds", [id + ":runtime:" + OcamlBytesMutationContract.RUNTIME_CAPABILITY]);
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
