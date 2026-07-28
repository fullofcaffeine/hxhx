package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesEncodingKind;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadContract;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadKind;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadResultKind;
import reflaxe.ocaml.lowered.OcamlBytesReadPlan;
import reflaxe.ocaml.lowered.OcamlBytesReadPlan.OcamlBytesReadPlanner;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedStandaloneExpressionPlan;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

/**
	Checks the revision-bound contract for exact read-only Bytes operations.

	The fixture uses real typed standard-library calls, verifies source-order
	evaluation and result carriers, then corrupts sealed facts so incomplete or
	stale records fail before OCaml syntax can be constructed.
**/
class BytesReadPlanFixture {
	static inline final PROGRAM_REVISION = "program:bytes-read-fixture";
	static inline final BODY_REVISION = "body:bytes-read-fixture";
	static inline final PIPELINE_REVISION = "pipeline:bytes-read-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(PROGRAM_REVISION);
		final cases = caseFields();
		final expected = [
			"length" => contract(OcamlBytesReadKind.Length, OcamlBytesEncodingKind.NotApplicable, OcamlBytesReadResultKind.IntValue, 0),
			"sub" => contract(OcamlBytesReadKind.Sub, OcamlBytesEncodingKind.NotApplicable, OcamlBytesReadResultKind.BytesValue, 2),
			"compare" => contract(OcamlBytesReadKind.Compare, OcamlBytesEncodingKind.NotApplicable, OcamlBytesReadResultKind.IntValue, 1),
			"getStringDefault" => contract(OcamlBytesReadKind.GetString, OcamlBytesEncodingKind.Omitted, OcamlBytesReadResultKind.StringValue, 2),
			"getStringExplicitNull" => contract(OcamlBytesReadKind.GetString, OcamlBytesEncodingKind.ExplicitNull, OcamlBytesReadResultKind.StringValue, 3),
			"getStringUtf8" => contract(OcamlBytesReadKind.GetString, OcamlBytesEncodingKind.UTF8, OcamlBytesReadResultKind.StringValue, 3),
			"getStringRawNative" => contract(OcamlBytesReadKind.GetString, OcamlBytesEncodingKind.RawNative, OcamlBytesReadResultKind.StringValue, 3),
			"toString" => contract(OcamlBytesReadKind.ToString, OcamlBytesEncodingKind.NotApplicable, OcamlBytesReadResultKind.StringValue, 0),
			"toHex" => contract(OcamlBytesReadKind.ToHex, OcamlBytesEncodingKind.NotApplicable, OcamlBytesReadResultKind.StringValue, 0),
			"receiverAndArgumentsInSourceOrder" => contract(OcamlBytesReadKind.Sub, OcamlBytesEncodingKind.NotApplicable, OcamlBytesReadResultKind.BytesValue,
				2)
		];

		final allDecisions:Array<OcamlBytesReadDecision> = [];
		for (name => expectedContract in expected) {
			final field = requireField(cases, name);
			final body = requireBody(field);
			final binding = binding(name);
			final first = new OcamlBytesReadPlanner(binding, representations).plan(body);
			final second = new OcamlBytesReadPlanner(binding, representations).plan(body);
			if (first.revision != second.revision)
				Context.error('Bytes read case "$name" has a non-deterministic plan revision.', field.pos);
			final decisions = first.decisions();
			if (decisions.length != 1)
				Context.error('Bytes read case "$name" expected one decision, received ${decisions.length}.', field.pos);
			final decision = decisions[0];
			final expectedOrder = decision.hasReceiver ? [-1].concat([for (index in 0...decision.argumentCount) index]) : [
				for (index in 0...decision.argumentCount)
					index
			];
			if (decision.kind != expectedContract.kind
				|| decision.encoding != expectedContract.encoding
				|| decision.resultKind != expectedContract.resultKind
				|| decision.argumentCount != expectedContract.argumentCount
				|| decision.evaluationOrder.join(",") != expectedOrder.join(",")
				|| !decision.hasReceiver
				|| decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				Context.error('Bytes read case "$name" disagrees with its typed read contract.', field.pos);
			}
			final occurrence = readOccurrence(body);
			if (occurrence == null || first.requireFor(occurrence, representations).id != decision.id)
				Context.error('Bytes read case "$name" did not resolve its exact sealed occurrence.', field.pos);
			allDecisions.push(decision);
		}

		for (name in [
			"fastGet",
			"get",
			"getUInt16",
			"getInt32",
			"getData",
			"deferredFloat",
			"deferredDouble",
			"deferredInt64"
		]) {
			final body = requireBody(requireField(cases, name));
			if (readOccurrence(body) != null)
				Context.error('Inline-expanded or deferred Bytes operation "$name" was admitted as a surviving call.', Context.currentPos());
		}

		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(PROGRAM_REVISION);
		for (decision in allDecisions)
			ledger.recordBytesRead(decision);
		final requirements = ledger.requirementsSorted();
		if (requirements.length != allDecisions.length)
			Context.error('Expected ${allDecisions.length} Bytes read requirements, received ${requirements.length}.', Context.currentPos());
		for (requirement in requirements) {
			if (requirement.semanticCapability != OcamlRuntimeRequirementLedger.HAXE_BYTES_READ
				|| requirement.subject.id != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
				|| requirement.rootModules.length != 1
				|| requirement.rootModules[0] != "HxBytes") {
				Context.error('Runtime requirement "${requirement.id}" does not select the exact HxBytes read contract.', Context.currentPos());
			}
		}

		final sample = Lambda.find(allDecisions, decision -> decision.kind == OcamlBytesReadKind.Length);
		if (sample == null)
			Context.error("The Bytes read fixture has no length decision.", Context.currentPos());
		expectThrows("duplicate-read", () -> new OcamlBytesReadPlan([sample, sample]));
		expectThrows("conflicting-read", () -> new OcamlBytesReadPlan([sample, reseal(sample, {bodyRevision: sample.bodyRevision + ":conflict"})]));
		expectThrows("invalid-read", () -> new OcamlBytesReadPlan([copy(sample, {kind: OcamlBytesReadKind.Sub})]));
		expectThrows("invalid-read", () -> new OcamlBytesReadPlan([copy(sample, {argumentCount: sample.argumentCount + 1})]));
		expectThrows("invalid-read-receiver", () -> new OcamlBytesReadPlan([
			reseal(sample, {receiverRepresentationId: "representation:Dynamic:internal-value"})
		]));
		expectThrows("invalid-read-result", () -> new OcamlBytesReadPlan([reseal(sample, {resultCarrierTypeId: "Obj.t"})]));
		expectThrows("invalid-read-encoding", () -> new OcamlBytesReadPlan([reseal(sample, {encoding: OcamlBytesEncodingKind.UTF8})]));
		expectThrows("invalid-read", () -> ledger.recordBytesRead(copy(sample, {calleeId: sample.calleeId + ":tampered"})));
		expectThrows("stale-read", () -> new OcamlBytesReadPlan([sample]).requirePlanBinding({
			functionId: sample.functionId,
			programRevision: sample.programRevision,
			bodyRevision: sample.bodyRevision + ":changed",
			pipelineRevision: sample.pipelineRevision
		}));

		final lengthBody = requireBody(requireField(cases, "length"));
		final lengthOccurrence = readOccurrence(lengthBody);
		final lengthDecision = sample;
		expectThrows("missing-read", () -> new OcamlBytesReadPlan([]).requireFor(lengthOccurrence, representations));
		final missingRepresentations = new OcamlRepresentationRegistry();
		missingRepresentations.beginProgram(PROGRAM_REVISION);
		expectThrows("missing-decision", () -> new OcamlBytesReadPlan([lengthDecision]).requireFor(lengthOccurrence, missingRepresentations));

		final standaloneRegistry = new OcamlFunctionPlanRegistry();
		standaloneRegistry.beginProgram(PROGRAM_REVISION);
		final standaloneOwner = "field-initializer:static:BytesReadCases::length";
		final firstStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, lengthBody, representations);
		final secondStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, lengthBody, representations);
		standaloneRegistry.requireStandaloneExpressionPlan(lengthBody, firstStandalone, representations);
		if (firstStandalone.binding.functionId != "standalone:" + standaloneOwner
			|| firstStandalone.binding.bodyRevision != secondStandalone.binding.bodyRevision
			|| firstStandalone.bytesReads.revision != secondStandalone.bytesReads.revision
			|| firstStandalone.bytesReads.decisions().length != 1) {
			Context.error("Standalone Bytes read planning did not preserve the exact deterministic expression binding.", Context.currentPos());
		}
		final staleStandalone:OcamlSealedStandaloneExpressionPlan = {
			binding: {
				functionId: firstStandalone.binding.functionId,
				programRevision: firstStandalone.binding.programRevision,
				bodyRevision: firstStandalone.binding.bodyRevision + ":changed",
				pipelineRevision: firstStandalone.binding.pipelineRevision
			},
			bytesMutations: firstStandalone.bytesMutations,
			bytesProducers: firstStandalone.bytesProducers,
			bytesReads: firstStandalone.bytesReads
		};
		expectThrows("stale-standalone-plan", () -> standaloneRegistry.requireStandaloneExpressionPlan(lengthBody, staleStandalone, representations));

		Sys.println("REFLAXE_OCAML_BYTES_READ_PLAN_FIXTURE:PASS");
		return macro null;
	}

	static function contract(kind:OcamlBytesReadKind, encoding:OcamlBytesEncodingKind, resultKind:OcamlBytesReadResultKind, argumentCount:Int):{
		kind:OcamlBytesReadKind,
		encoding:OcamlBytesEncodingKind,
		resultKind:OcamlBytesReadResultKind,
		argumentCount:Int
	} {
		return {
			kind: kind,
			encoding: encoding,
			resultKind: resultKind,
			argumentCount: argumentCount
		};
	}

	static function binding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "BytesReadCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: BODY_REVISION + ":" + name,
			pipelineRevision: PIPELINE_REVISION
		};
	}

	static function caseFields():Map<String, ClassField> {
		return switch (Context.getType("BytesReadCases")) {
			case TInst(classRef, _):
				[for (field in classRef.get().statics.get()) field.name => field];
			case _:
				Context.error("BytesReadCases did not resolve to a class.", Context.currentPos());
		}
	}

	static function requireField(fields:Map<String, ClassField>, name:String):ClassField {
		final field = fields.get(name);
		if (field == null)
			Context.error('Missing typed Bytes read case "$name".', Context.currentPos());
		return field;
	}

	static function requireBody(field:ClassField):TypedExpr {
		final body = field.expr();
		if (body == null)
			Context.error('Bytes read case "${field.name}" has no typed body.', field.pos);
		return body;
	}

	static function readOccurrence(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			if (OcamlBytesReadPlan.admittedKind(expression) != null) {
				found = expression;
				return;
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		return found;
	}

	static function copy(decision:OcamlBytesReadDecision, changes:Dynamic):OcamlBytesReadDecision {
		final value:Dynamic = {};
		for (field in Reflect.fields(decision))
			Reflect.setField(value, field, Reflect.field(decision, field));
		for (field in Reflect.fields(changes))
			Reflect.setField(value, field, Reflect.field(changes, field));
		return cast value;
	}

	static function reseal(decision:OcamlBytesReadDecision, changes:Dynamic):OcamlBytesReadDecision {
		final value:Dynamic = copy(decision, changes);
		final changed:OcamlBytesReadDecision = cast value;
		final id = OcamlBytesReadContract.idFor(changed);
		Reflect.setField(value, "id", id);
		Reflect.setField(value, "runtimeRequirementIds", [id + ":runtime:" + OcamlBytesReadContract.RUNTIME_CAPABILITY]);
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
