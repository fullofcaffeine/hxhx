package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessAliasPolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessBoundsPolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessContract;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessInvocationKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessMutationPolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessResultKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessValuePolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan.OcamlBytesAccessPlanner;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

/**
	Proves that the real target override leaves exact byte-access calls to seal.

	The fixture checks deterministic occurrence plans and representation
	decisions, then corrupts individual facts so stale or incomplete records
	cannot reach OCaml syntax or runtime packaging.
**/
class BytesAccessPlanFixture {
	static inline final PROGRAM_REVISION = "program:bytes-access-fixture";
	static inline final BODY_REVISION = "body:bytes-access-fixture";
	static inline final PIPELINE_REVISION = "pipeline:bytes-access-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(PROGRAM_REVISION);
		final cases = caseFields();
		final decisions:Array<OcamlBytesAccessDecision> = [];
		final expectedKinds = [
			"get" => OcamlBytesAccessKind.Get,
			"getNullablePosition" => OcamlBytesAccessKind.Get,
			"set" => OcamlBytesAccessKind.Set,
			"setNullableValue" => OcamlBytesAccessKind.Set,
			"getData" => OcamlBytesAccessKind.GetData,
			"fastGet" => OcamlBytesAccessKind.FastGet,
			"getInSourceOrder" => OcamlBytesAccessKind.Get,
			"setInSourceOrder" => OcamlBytesAccessKind.Set,
			"getDataInSourceOrder" => OcamlBytesAccessKind.GetData,
			"fastGetInSourceOrder" => OcamlBytesAccessKind.FastGet
		];
		for (name => kind in expectedKinds) {
			final field = requireField(cases, name);
			final body = requireBody(field);
			final binding = binding(name);
			final first = new OcamlBytesAccessPlanner(binding, representations).plan(body);
			final second = new OcamlBytesAccessPlanner(binding, representations).plan(body);
			if (first.revision != second.revision)
				Context.error('Bytes access case "$name" has a non-deterministic plan revision.', field.pos);
			final planned = first.decisions();
			if (planned.length != 1)
				Context.error('Bytes access case "$name" expected one decision, received ${planned.length}: ${TypedExprTools.toString(body)}', field.pos);
			final decision = planned[0];
			final invocation = kind == OcamlBytesAccessKind.FastGet ? OcamlBytesAccessInvocationKind.Static : OcamlBytesAccessInvocationKind.Instance;
			final expectedOrder = invocation == OcamlBytesAccessInvocationKind.Instance ? [-1].concat([
				for (index in 0...decision.argumentCount)
					index
			]) : [for (index in 0...decision.argumentCount) index];
			if (decision.kind != kind
				|| decision.invocationKind != invocation
				|| decision.evaluationOrder.join(",") != expectedOrder.join(",")
				|| decision.boundsPolicy != OcamlBytesAccessContract.boundsPolicy(kind)
				|| decision.valuePolicy != OcamlBytesAccessContract.valuePolicy(kind)
				|| decision.mutationPolicy != OcamlBytesAccessContract.mutationPolicy(kind)
				|| decision.aliasPolicy != OcamlBytesAccessContract.aliasPolicy(kind)
				|| decision.resultKind != OcamlBytesAccessContract.resultKind(kind)
				|| decision.runtimeOperation != OcamlBytesAccessContract.fieldName(kind)) {
				Context.error('Bytes access case "$name" disagrees with its typed access contract.', field.pos);
			}
			if (kind == OcamlBytesAccessKind.GetData) {
				if (decision.resultSemanticTypeId != OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
					|| decision.resultCarrierTypeId != OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID
					|| decision.aliasPolicy != OcamlBytesAccessAliasPolicy.SharedNativeDataAlias
					|| decision.mutationPolicy != OcamlBytesAccessMutationPolicy.ReturnMutableAlias) {
					Context.error('Bytes access case "$name" did not seal the mutable BytesData alias.', field.pos);
				}
			}
			if (kind == OcamlBytesAccessKind.Set
				&& (decision.valuePolicy != OcamlBytesAccessValuePolicy.MaskLowEightBits
					|| decision.resultKind != OcamlBytesAccessResultKind.EffectOnlyVoid)) {
				Context.error('Bytes access case "$name" did not seal low-byte mutation and effect-only Void.', field.pos);
			}
			if (kind == OcamlBytesAccessKind.FastGet
				&& (decision.argumentSemanticTypeIds[0] != OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
					|| decision.boundsPolicy != OcamlBytesAccessBoundsPolicy.NativeDataChecked
					|| decision.receiverRepresentationId.length != 0)) {
				Context.error('Bytes access case "$name" did not seal the exact checked BytesData read.', field.pos);
			}
			if (name == "getNullablePosition") {
				requireNullableIntConversion(decision, 0, field.pos);
			} else if (name == "setNullableValue") {
				requireNullableIntConversion(decision, 1, field.pos);
			}
			final occurrence = accessOccurrence(body);
			if (occurrence == null || first.requireFor(occurrence, representations).id != decision.id)
				Context.error('Bytes access case "$name" did not resolve its exact sealed occurrence.', field.pos);
			decisions.push(decision);
		}

		final lookalike = requireBody(requireField(cases, "userLookalike"));
		if (new OcamlBytesAccessPlanner(binding("userLookalike"), representations).plan(lookalike).decisions().length != 0)
			Context.error("User-defined access lookalikes were admitted as haxe.io.Bytes calls.", Context.currentPos());

		final dataRepresentation = representations.selectExactBytesData(reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain.InternalValue);
		if (dataRepresentation.semanticTypeId != OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
			|| dataRepresentation.carrierTypeId != OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID
			|| dataRepresentation.proof.id != OcamlBytesRepresentationContract.DATA_PROOF_ID) {
			Context.error("The exact BytesData representation does not preserve the target-native mutable alias.", Context.currentPos());
		}

		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(PROGRAM_REVISION);
		for (decision in decisions)
			ledger.recordBytesAccess(decision);
		final requirements = ledger.requirementsSorted();
		if (requirements.length != decisions.length)
			Context.error('Expected ${decisions.length} Bytes access requirements, received ${requirements.length}.', Context.currentPos());
		for (requirement in requirements) {
			if (requirement.semanticCapability != OcamlRuntimeRequirementLedger.HAXE_BYTES_ACCESS
				|| requirement.subject.id != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
				|| requirement.rootModules.join(",") != "HxBytes") {
				Context.error('Runtime requirement "${requirement.id}" does not select the exact HxBytes access contract.', Context.currentPos());
			}
		}

		final sample = Lambda.find(decisions, decision -> decision.kind == OcamlBytesAccessKind.GetData
			&& decision.functionId == "BytesAccessCases.getData");
		if (sample == null)
			Context.error("The Bytes access fixture has no getData decision.", Context.currentPos());
		expectThrows("duplicate-access", () -> new OcamlBytesAccessPlan([sample, sample]));
		expectThrows("conflicting-access", () -> new OcamlBytesAccessPlan([sample, reseal(sample, {bodyRevision: sample.bodyRevision + ":conflict"})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([copy(sample, {kind: OcamlBytesAccessKind.Get})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(sample, {evaluationOrder: []})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(sample, {aliasPolicy: OcamlBytesAccessAliasPolicy.NoNewAlias})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(sample, {occurrenceId: "bytes-access-occurrence:not-a-digest"})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(sample, {boundsPolicy: OcamlBytesAccessBoundsPolicy.DeclaredBytesChecked})
		]));
		expectThrows("invalid-access-result", () -> new OcamlBytesAccessPlan([reseal(sample, {resultCarrierTypeId: "Obj.t"})]));
		expectThrows("invalid-access", () -> ledger.recordBytesAccess(copy(sample, {calleeId: sample.calleeId + ":tampered"})));
		expectThrows("stale-access", () -> new OcamlBytesAccessPlan([sample]).requirePlanBinding({
			functionId: sample.functionId,
			programRevision: sample.programRevision,
			bodyRevision: sample.bodyRevision + ":changed",
			pipelineRevision: sample.pipelineRevision
		}));

		final getDataBody = requireBody(requireField(cases, "getData"));
		final getDataOccurrence = accessOccurrence(getDataBody);
		expectThrows("missing-access", () -> new OcamlBytesAccessPlan([]).requireFor(getDataOccurrence, representations));
		final missingRepresentations = new OcamlRepresentationRegistry();
		missingRepresentations.beginProgram(PROGRAM_REVISION);
		expectThrows("missing-decision", () -> new OcamlBytesAccessPlan([sample]).requireFor(getDataOccurrence, missingRepresentations));
		final firstSharedSpanOccurrence:TypedExpr = {
			expr: getDataOccurrence.expr,
			pos: getDataOccurrence.pos,
			t: getDataOccurrence.t
		};
		final secondSharedSpanOccurrence:TypedExpr = {
			expr: getDataOccurrence.expr,
			pos: getDataOccurrence.pos,
			t: getDataOccurrence.t
		};
		final sharedSpanRoot:TypedExpr = {
			expr: TBlock([firstSharedSpanOccurrence, secondSharedSpanOccurrence]),
			pos: getDataOccurrence.pos,
			t: getDataOccurrence.t
		};
		final sharedSpanPlan = new OcamlBytesAccessPlanner(binding("sharedSpan"), representations).plan(sharedSpanRoot);
		final sharedSpanDecisions = sharedSpanPlan.decisions();
		if (sharedSpanDecisions.length != 2
			|| sharedSpanDecisions[0].occurrenceId == sharedSpanDecisions[1].occurrenceId
			|| sharedSpanDecisions[0].source.file != sharedSpanDecisions[1].source.file
			|| sharedSpanDecisions[0].source.min != sharedSpanDecisions[1].source.min
			|| sharedSpanDecisions[0].source.max != sharedSpanDecisions[1].source.max
			|| sharedSpanPlan.requireFor(firstSharedSpanOccurrence, representations)
				.id == sharedSpanPlan.requireFor(secondSharedSpanOccurrence, representations)
				.id) {
			Context.error("Distinct typed Bytes accesses with one shared source span did not retain exact structural identities.", Context.currentPos());
		}

		final standaloneRegistry = new OcamlFunctionPlanRegistry();
		standaloneRegistry.beginProgram(PROGRAM_REVISION);
		final standaloneOwner = "field-initializer:static:BytesAccessCases::data";
		final firstStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, getDataBody, representations);
		final secondStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, getDataBody, representations);
		standaloneRegistry.requireStandaloneExpressionPlan(getDataBody, firstStandalone, representations);
		if (firstStandalone.bytesAccesses.revision != secondStandalone.bytesAccesses.revision
			|| firstStandalone.bytesAccesses.decisions().length != 1) {
			Context.error("Standalone Bytes access planning did not preserve the exact expression binding.", Context.currentPos());
		}

		Sys.println("REFLAXE_OCAML_BYTES_ACCESS_PLAN_FIXTURE:PASS");
		return macro null;
	}

	static function requireNullableIntConversion(decision:OcamlBytesAccessDecision, index:Int, position:haxe.macro.Expr.Position):Void {
		if (decision.argumentInputSemanticTypeIds[index] != "Null<Int>"
			|| decision.argumentSemanticTypeIds[index] != "Int"
			|| decision.argumentConversions[index] != OcamlBytesAccessArgumentConversion.RequireNonNullInt) {
			Context.error('Bytes access "${decision.id}" did not seal nullable Int argument $index.', position);
		}
	}

	static function binding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "BytesAccessCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: BODY_REVISION + ":" + name,
			pipelineRevision: PIPELINE_REVISION
		};
	}

	static function caseFields():Map<String, ClassField> {
		return switch (Context.getType("BytesAccessCases")) {
			case TInst(classRef, _): [for (field in classRef.get().statics.get()) field.name => field];
			case _: Context.error("BytesAccessCases did not resolve to a class.", Context.currentPos());
		}
	}

	static function requireField(fields:Map<String, ClassField>, name:String):ClassField {
		final field = fields.get(name);
		if (field == null)
			Context.error('Missing typed Bytes access case "$name".', Context.currentPos());
		return field;
	}

	static function requireBody(field:ClassField):TypedExpr {
		final body = field.expr();
		if (body == null)
			Context.error('Bytes access case "${field.name}" has no typed body.', field.pos);
		return body;
	}

	static function accessOccurrence(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			if (OcamlBytesAccessPlan.admittedOccurrence(expression) != null) {
				found = expression;
				return;
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		return found;
	}

	static function copy(decision:OcamlBytesAccessDecision, changes:Dynamic):OcamlBytesAccessDecision {
		final value:Dynamic = {};
		for (field in Reflect.fields(decision))
			Reflect.setField(value, field, Reflect.field(decision, field));
		for (field in Reflect.fields(changes))
			Reflect.setField(value, field, Reflect.field(changes, field));
		return cast value;
	}

	static function reseal(decision:OcamlBytesAccessDecision, changes:Dynamic):OcamlBytesAccessDecision {
		final value:Dynamic = copy(decision, changes);
		final changed:OcamlBytesAccessDecision = cast value;
		final id = OcamlBytesAccessContract.idFor(changed);
		Reflect.setField(value, "id", id);
		Reflect.setField(value, "runtimeRequirementIds", [id + ":runtime:" + OcamlBytesAccessContract.RUNTIME_CAPABILITY]);
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
