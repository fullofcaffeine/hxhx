package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import haxe.ds.ObjectMap;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralEvaluationKind;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerLookup;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerPlanner;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlNormalizedRepresentedArray;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/**
	Checks compiler-owned construction records for direct represented array literals.

	An actively supported `Array<Int>` literal must be described before OCaml
	syntax is built. A later `Array<String>` family can create the same kind of
	detached plain-data record, but it is deliberately absent from the syntax
	lookup until a separate hard cut admits its consumers. Both records fix the
	carrier and the exact order in which the container and elements are evaluated.
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

		for (name in ["bools", "strings", "emptyStrings", "effectfulStrings", "nested"])
			if (new OcamlArrayLiteralProducerPlanner(binding(name), representations).plan(fieldBody(requiredField(fields, name))).decisions().length != 0)
				Context.error('Unsupported array literal case "$name" was admitted by the direct Array<Int> producer.', requiredField(fields, name).pos);

		final stringLiteral = firstLiteral(fieldBody(requiredField(fields, "strings")));
		if (stringLiteral == null)
			Context.error("The strings case has no typed array literal.", Context.currentPos());
		final stringNormalized = normalizedArray("String");
		if (OcamlRepresentationRegistry.normalizedDirectFlatArray(stringLiteral.t) != null
			|| OcamlArrayLiteralProducerPlan.isAdmittedLiteral(stringLiteral)) {
			Context.error("The dormant String producer unexpectedly entered the active Array<Int> admission path.", stringLiteral.pos);
		}
		final stringPlanner = new OcamlArrayLiteralProducerPlanner(binding("strings"), representations);
		final firstStringDecision = stringPlanner.planDetachedLiteral(stringLiteral, stringNormalized, 0);
		final secondStringDecision = stringPlanner.planDetachedLiteral(stringLiteral, stringNormalized, 0);
		final expectedStringDecision = directStringDecision(stringLiteral, binding("strings"), representations);
		final firstStringPlan = new OcamlArrayLiteralProducerPlan([firstStringDecision]);
		final secondStringPlan = new OcamlArrayLiteralProducerPlan([secondStringDecision]);
		if (firstStringPlan.revision != secondStringPlan.revision
			|| firstStringPlan.revision != OcamlArrayLiteralProducerContract.planRevision([expectedStringDecision])
			|| firstStringDecision.id != expectedStringDecision.id
			|| firstStringDecision.arraySemanticTypeId != "Array<String>"
			|| firstStringDecision.arrayCarrierTypeId != "string HxArray.t"
			|| firstStringDecision.resultRepresentationId != "representation:Array<String>:internal-value"
			|| firstStringDecision.arrayDescriptorId != "represented-array:Array<String>"
			|| firstStringDecision.elementSemanticTypeId != "String"
			|| firstStringDecision.elementCarrierTypeId != "string"
			|| firstStringDecision.elementRepresentationId != "representation:String:array-element"
			|| firstStringDecision.proofId != "direct-array-string-literal-construction-v1"
			|| firstStringDecision.elements.length != 2
			|| firstStringDecision.evaluationSchedule.length != 6) {
			Context.error("The detached String producer disagrees with its independently authored descriptor and construction contract.", stringLiteral.pos);
		}
		switch (firstStringPlan.syntaxLookup(stringLiteral)) {
			case OcamlArrayLiteralProducerLookup.Unknown:
			case _:
				Context.error("A detached String producer became reachable from target syntax.", stringLiteral.pos);
		}
		final forgedLookup:ObjectMap<TypedExpr, Null<String>> = new ObjectMap();
		forgedLookup.set(stringLiteral, firstStringDecision.id);
		final forgedStringPlan = new OcamlArrayLiteralProducerPlan([firstStringDecision], forgedLookup);
		switch (forgedStringPlan.syntaxLookup(stringLiteral)) {
			case OcamlArrayLiteralProducerLookup.Required(_):
			case _:
				Context.error("The forged lookup fixture did not reach the final admission guard.", stringLiteral.pos);
		}
		expectThrows("unadmitted-producer", () -> forgedStringPlan.requireFor(stringLiteral, representations));

		for (name => elementCount in ["emptyStrings" => 0, "effectfulStrings" => 2]) {
			final literal = firstLiteral(fieldBody(requiredField(fields, name)));
			if (literal == null)
				Context.error('The $name case has no typed array literal.', requiredField(fields, name).pos);
			final decision = new OcamlArrayLiteralProducerPlanner(binding(name), representations).planDetachedLiteral(literal, stringNormalized, 0);
			if (decision.elements.length != elementCount
				|| decision.evaluationSchedule.length != elementCount * 2 + 2
				|| decision.evaluationSchedule[0].kind != OcamlArrayLiteralEvaluationKind.CreateArray
				|| decision.evaluationSchedule[decision.evaluationSchedule.length - 1].kind != OcamlArrayLiteralEvaluationKind.ResultArray) {
				Context.error('The detached String producer case "$name" changed its create/evaluate/store/result schedule.', literal.pos);
			}
		}

		final intLiteral = firstLiteral(fieldBody(requiredField(fields, "ordered")));
		final boolLiteral = firstLiteral(fieldBody(requiredField(fields, "bools")));
		if (intLiteral == null || boolLiteral == null)
			Context.error("The negative producer cases are missing typed literals.", Context.currentPos());
		expectThrows("typed-identity-mismatch", () -> stringPlanner.planDetachedLiteral(intLiteral, stringNormalized, 0));
		expectThrows("typed-identity-mismatch", () -> stringPlanner.planDetachedLiteral(stringLiteral, normalizedArray("Int"), 0));
		expectThrows("typed-identity-mismatch", () -> stringPlanner.planDetachedLiteral(boolLiteral, normalizedArray("Bool"), 0));
		expectThrows("not-array-literal", () -> stringPlanner.planDetachedLiteral(fieldBody(requiredField(fields, "strings")), stringNormalized, 0));
		expectThrows("invalid-literal-ordinal", () -> stringPlanner.planDetachedLiteral(stringLiteral, stringNormalized, -1));
		expectThrows("stale-representation",
			() -> new OcamlArrayLiteralProducerPlanner(changedProgramBinding("strings"),
				representations).planDetachedLiteral(stringLiteral, stringNormalized, 0));
		expectThrows("unsupported-element-family", () -> OcamlArrayLiteralProducerContract.proofIdFor("Bool"));
		expectThrows("unsupported-element-family", () -> OcamlArrayLiteralProducerContract.proofClaimFor("Bool"));
		expectThrows("invalid-producer", () -> new OcamlArrayLiteralProducerPlan([copy(firstStringDecision, {arraySemanticTypeId: "Array<Int>"})]));
		expectThrows("invalid-producer", () -> new OcamlArrayLiteralProducerPlan([copy(firstStringDecision, {arrayCarrierTypeId: "int HxArray.t"})]));
		expectThrows("invalid-producer", () -> new OcamlArrayLiteralProducerPlan([copy(firstStringDecision, {elementSemanticTypeId: "Int"})]));
		expectThrows("invalid-producer", () -> new OcamlArrayLiteralProducerPlan([
			copy(firstStringDecision, {proofId: OcamlArrayLiteralProducerContract.INT_PROOF_ID})
		]));
		expectThrows("invalid-producer", () -> new OcamlArrayLiteralProducerPlan([copy(firstStringDecision, {proofClaim: "changed"})]));
		expectThrows("invalid-element-producer", () -> {
			final corrupted = copy(firstStringDecision, {});
			final corruptedElements:Dynamic = corrupted.elements;
			Reflect.setField(corruptedElements[0], "carrierTypeId", "int");
			new OcamlArrayLiteralProducerPlan([corrupted]);
		});

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

	static function changedProgramBinding(name:String):OcamlFunctionPlanBinding {
		final value = binding(name);
		return {
			functionId: value.functionId,
			programRevision: value.programRevision + ":changed",
			bodyRevision: value.bodyRevision,
			pipelineRevision: value.pipelineRevision
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

	static function normalizedArray(elementSemanticTypeId:String):OcamlNormalizedRepresentedArray {
		return {
			arraySemanticTypeId: 'Array<$elementSemanticTypeId>',
			elementSemanticTypeId: elementSemanticTypeId,
			sourceForm: "direct-builtin-array",
			closureKind: "closed-monomorphic",
			outerWrapperKind: "none",
			nestingKind: "flat"
		};
	}

	/**
		Builds the independent expected record for one dormant String literal.

		The production planner does not admit this occurrence yet. Keeping the
		expectation here makes the red test ask one precise question: can the shared
		plain-data contract validate a String decision whose descriptor and schedule
		already agree with the current registry?
	**/
	static function directStringDecision(literal:TypedExpr, owner:OcamlFunctionPlanBinding,
			representations:OcamlRepresentationRegistry):OcamlArrayLiteralProducerDecision {
		final normalized = normalizedArray("String");
		final result = representations.selectNormalizedRepresentedArray(normalized, OcamlRepresentationDomain.InternalValue);
		final descriptor = representations.requireRepresentedArray(result.arrayDescriptorId, result.arrayDescriptorRevision, owner.programRevision);
		final items = switch (literal.expr) {
			case TArrayDecl(values): values;
			case _: Context.error("The independent String producer expectation requires a typed array literal.", literal.pos);
		};
		final source = OcamlLoweredOrigin.sourceSpan(literal.pos);
		final id = OcamlArrayLiteralProducerContract.idFor(owner, source, 0, result.id, result.revision, descriptor.id, descriptor.revision);
		final elements = [
			for (index in 0...items.length) {
				final elementSource = OcamlLoweredOrigin.sourceSpan(items[index].pos);
				{
					id: OcamlArrayLiteralProducerContract.elementIdFor(id, index, elementSource, descriptor.elementRepresentationId,
						descriptor.elementRepresentationRevision),
					index: index,
					source: elementSource,
					semanticTypeId: descriptor.elementSemanticTypeId,
					carrierTypeId: descriptor.elementCarrierTypeId,
					representationId: descriptor.elementRepresentationId,
					representationRevision: descriptor.elementRepresentationRevision
				};
			}
		];
		return {
			id: id,
			source: source,
			literalOrdinal: 0,
			arraySemanticTypeId: descriptor.arraySemanticTypeId,
			arrayCarrierTypeId: descriptor.arrayCarrierTypeId,
			resultRepresentationId: result.id,
			resultRepresentationRevision: result.revision,
			arrayDescriptorId: descriptor.id,
			arrayDescriptorRevision: descriptor.revision,
			elementSemanticTypeId: descriptor.elementSemanticTypeId,
			elementCarrierTypeId: descriptor.elementCarrierTypeId,
			elementRepresentationId: descriptor.elementRepresentationId,
			elementRepresentationRevision: descriptor.elementRepresentationRevision,
			elements: elements,
			evaluationSchedule: OcamlArrayLiteralProducerContract.schedule(elements),
			constructionPolicy: "create-then-evaluate-and-push-in-order",
			proofId: "direct-array-string-literal-construction-v1",
			proofClaim: "This occurrence allocates one direct represented Array<String>, evaluates each exact String element once in increasing source order, stores each evaluated carrier once, and returns the same mutable HxArray object. The claim ends at literal construction and does not admit another array shape, element family, call, return, field, typed catch, or public/native boundary.",
			profileEligibility: ["metal", "portable"],
			functionId: owner.functionId,
			programRevision: owner.programRevision,
			bodyRevision: owner.bodyRevision,
			pipelineRevision: owner.pipelineRevision
		};
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
