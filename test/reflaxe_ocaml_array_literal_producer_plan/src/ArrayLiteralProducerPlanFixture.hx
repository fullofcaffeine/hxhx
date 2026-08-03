package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralEvaluationKind;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerPlanner;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/**
	Checks the compiler-owned construction contract for direct `Array<Int>` literals.

	A supported literal must be described before OCaml syntax is built. The
	description fixes the represented array carrier and the exact order in which
	the container and its elements are evaluated, so the final printer cannot
	quietly invent or duplicate those source-language effects.
**/
class ArrayLiteralProducerPlanFixture {
	static inline final PROGRAM_REVISION = "program:array-literal-producer-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(PROGRAM_REVISION);
		final fields = caseFields();
		final admitted = ["ordered" => 2, "empty" => 0];
		final decisions:Array<OcamlArrayLiteralProducerDecision> = [];
		for (name => elementCount in admitted) {
			final field = requiredField(fields, name);
			final body = fieldBody(field);
			final binding = binding(name);
			final first = new OcamlArrayLiteralProducerPlanner(binding, representations).plan(body);
			final second = new OcamlArrayLiteralProducerPlanner(binding, representations).plan(body);
			if (first.revision != second.revision)
				Context.error('Array literal producer case "$name" has a non-deterministic plan revision.', field.pos);
			final planned = first.decisions();
			if (planned.length != 1)
				Context.error('Array literal producer case "$name" expected one decision, received ${planned.length}.', field.pos);
			final decision = planned[0];
			final literal = firstLiteral(body);
			if (literal == null || first.requireFor(literal, representations).id != decision.id)
				Context.error('Array literal producer case "$name" did not resolve its exact typed occurrence.', field.pos);
			if (decision.elements.length != elementCount
				|| decision.evaluationSchedule.length != elementCount * 2 + 2
				|| decision.evaluationSchedule[0].kind != OcamlArrayLiteralEvaluationKind.CreateArray
				|| decision.evaluationSchedule[decision.evaluationSchedule.length - 1].kind != OcamlArrayLiteralEvaluationKind.ResultArray
				|| decision.resultRepresentationId != "representation:Array<Int>:internal-value"
				|| decision.arrayDescriptorId != "represented-array:Array<Int>"
				|| decision.elementRepresentationId != "representation:Int:array-element"
				|| decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				Context.error('Array literal producer case "$name" disagrees with its represented construction contract.', field.pos);
			}
			for (index in 0...decision.elements.length) {
				final evaluate = decision.evaluationSchedule[index * 2 + 1];
				final store = decision.evaluationSchedule[index * 2 + 2];
				if (decision.elements[index].index != index
					|| evaluate.kind != OcamlArrayLiteralEvaluationKind.EvaluateElement
					|| store.kind != OcamlArrayLiteralEvaluationKind.StoreElement
					|| evaluate.elementIndex != index
					|| store.elementIndex != index
					|| evaluate.elementProducerId != decision.elements[index].id
					|| store.elementProducerId != decision.elements[index].id) {
					Context.error('Array literal producer case "$name" does not evaluate and store element $index exactly once in order.', field.pos);
				}
			}
			decisions.push(decision);
		}

		for (name in ["bools", "strings", "nested"])
			if (new OcamlArrayLiteralProducerPlanner(binding(name), representations).plan(fieldBody(requiredField(fields, name))).decisions().length != 0)
				Context.error('Unsupported array literal case "$name" was admitted by the direct Array<Int> producer.', requiredField(fields, name).pos);

		final sample = decisions[0];
		final sampleLiteral = firstLiteral(fieldBody(requiredField(fields, "ordered")));
		if (sampleLiteral == null)
			Context.error("The ordered case has no typed array literal.", Context.currentPos());
		expectThrows("duplicate-producer", () -> new OcamlArrayLiteralProducerPlan([sample, sample]));
		expectThrows("invalid-producer", () -> new OcamlArrayLiteralProducerPlan([copy(sample, {arrayDescriptorRevision: changedRevision()})]));
		expectThrows("invalid-producer", () -> new OcamlArrayLiteralProducerPlan([copy(sample, {resultRepresentationRevision: "sha256:truncated"})]));
		expectThrows("invalid-element-producer", () -> new OcamlArrayLiteralProducerPlan([copy(sample, {elements: [sample.elements[1], sample.elements[0]]})]));
		expectThrows("invalid-element-producer", () -> new OcamlArrayLiteralProducerPlan([copy(sample, {elements: [sample.elements[0], sample.elements[0]]})]));
		final reorderedSchedule = sample.evaluationSchedule.copy();
		final swap = reorderedSchedule[1];
		reorderedSchedule[1] = reorderedSchedule[2];
		reorderedSchedule[2] = swap;
		expectThrows("invalid-evaluation-schedule", () -> new OcamlArrayLiteralProducerPlan([copy(sample, {evaluationSchedule: reorderedSchedule})]));
		expectThrows("stale-producer", () -> new OcamlArrayLiteralProducerPlan([sample]).requirePlanBinding({
			functionId: sample.functionId,
			programRevision: sample.programRevision,
			bodyRevision: sample.bodyRevision + ":changed",
			pipelineRevision: sample.pipelineRevision
		}));
		expectThrows("unknown-occurrence", () -> new OcamlArrayLiteralProducerPlan([]).requireFor(sampleLiteral, representations));
		final missingRepresentations = new OcamlRepresentationRegistry();
		missingRepresentations.beginProgram(PROGRAM_REVISION);
		expectThrows("missing-decision", () -> new OcamlArrayLiteralProducerPlan([sample]).requireRepresentations(missingRepresentations));

		Sys.println("REFLAXE_OCAML_ARRAY_LITERAL_PRODUCER_PLAN_FIXTURE:PASS");
		return macro null;
	}

	static function binding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "ArrayLiteralProducerCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: "body:array-literal-producer-fixture:" + name,
			pipelineRevision: "pipeline:array-literal-producer-fixture"
		};
	}

	static function requiredField(fields:Map<String, ClassField>, name:String):ClassField {
		final field = fields.get(name);
		if (field == null)
			Context.error('Missing typed array literal case "$name".', Context.currentPos());
		return field;
	}

	static function fieldBody(field:ClassField):TypedExpr {
		final expression = field.expr();
		if (expression == null)
			Context.error('Array literal case "${field.name}" has no typed body.', field.pos);
		return switch (expression.expr) {
			case TFunction(tfunc): tfunc.expr;
			case _: expression;
		};
	}

	static function firstLiteral(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			switch (expression.expr) {
				case TArrayDecl(_):
					found = expression;
				case TFunction(_):
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}
		visit(body);
		return found;
	}

	static function changedRevision():String {
		return "sha256:" + StringTools.lpad("", "0", 64);
	}

	static function copy(decision:OcamlArrayLiteralProducerDecision, changes:Dynamic):OcamlArrayLiteralProducerDecision {
		final value:Dynamic = OcamlArrayLiteralProducerPlan.copyDecision(decision);
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

	static function caseFields():Map<String, ClassField> {
		return switch (Context.getType("ArrayLiteralProducerCases")) {
			case TInst(classRef, _):
				[for (field in classRef.get().statics.get()) field.name => field];
			case _:
				Context.error("ArrayLiteralProducerCases did not resolve to a class.", Context.currentPos());
		};
	}
}
