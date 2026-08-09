package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.ast.OcamlArrayLiteralSyntax;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralEvaluationKind;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerLookup;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerPlanner;
import reflaxe.ocaml.lowered.OcamlDirectArraySourceIdentity;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlNormalizedRepresentedArray;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

/**
	Checks compiler-owned construction records for direct represented array literals.

	An actively supported `Array<Int>` or `Array<String>` literal must be described
	before OCaml syntax is built. Both records fix the carrier and the exact order
	in which the container and elements are evaluated. General represented-array
	admission remains Int-only, so this literal proof cannot silently enable a
	String-array local, place, call, return, field, or public boundary.
**/
class ArrayLiteralProducerPlanFixture {
	static inline final PROGRAM_REVISION = "program:array-literal-producer-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(PROGRAM_REVISION);
		final fields = caseFields();
		final admitted = [
			{name: "ordered", elementCount: 2, elementSemanticTypeId: "Int"},
			{name: "empty", elementCount: 0, elementSemanticTypeId: "Int"},
			{name: "strings", elementCount: 2, elementSemanticTypeId: "String"},
			{name: "emptyStrings", elementCount: 0, elementSemanticTypeId: "String"},
			{name: "effectfulStrings", elementCount: 2, elementSemanticTypeId: "String"}
		];
		final decisions:Array<OcamlArrayLiteralProducerDecision> = [];
		for (admittedCase in admitted) {
			final name = admittedCase.name;
			final elementCount = admittedCase.elementCount;
			final elementSemanticTypeId = admittedCase.elementSemanticTypeId;
			final arraySemanticTypeId = 'Array<$elementSemanticTypeId>';
			final arrayCarrierTypeId = elementSemanticTypeId == "Int" ? "int HxArray.t" : "string HxArray.t";
			final elementCarrierTypeId = elementSemanticTypeId == "Int" ? "int" : "string";
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
				|| decision.arraySemanticTypeId != arraySemanticTypeId
				|| decision.arrayCarrierTypeId != arrayCarrierTypeId
				|| decision.resultRepresentationId != 'representation:$arraySemanticTypeId:internal-value'
				|| decision.arrayDescriptorId != 'represented-array:$arraySemanticTypeId'
				|| decision.elementSemanticTypeId != elementSemanticTypeId
				|| decision.elementCarrierTypeId != elementCarrierTypeId
				|| decision.elementRepresentationId != 'representation:$elementSemanticTypeId:array-element'
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
			final runtimeRequirementId = decision.id + ":runtime:haxe-array-literal-construction";
			final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
			if (decision.runtimeRequirementIds.length != 1 || decision.runtimeRequirementIds[0] != runtimeRequirementId)
				Context.error('Array literal producer case "$name" has no exact HxArray construction requirement.', field.pos);
			if (decision.runtimeUseOccurrences.length != elementCount + 1)
				Context.error('Array literal producer case "$name" does not own one create use and one push use per element.', field.pos);
			final createUse = decision.runtimeUseOccurrences[0];
			if (createUse.id != decision.id + ":runtime-use:create"
				|| createUse.planRevision != runtimePlanRevision
				|| createUse.ownerId != decision.id
				|| createUse.requirementId != runtimeRequirementId
				|| createUse.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
				|| createUse.exactSymbol != "HxArray.create"
				|| createUse.role != "create-array"
				|| createUse.order != 0
				|| createUse.cardinality != 1) {
				Context.error('Array literal producer case "$name" has an invalid HxArray.create occurrence.', field.pos);
			}
			for (index in 0...decision.elements.length) {
				final pushUse = decision.runtimeUseOccurrences[index + 1];
				final storeStep = decision.evaluationSchedule[index * 2 + 2];
				if (pushUse.id != decision.id + ':runtime-use:push:$index'
					|| pushUse.planRevision != runtimePlanRevision
					|| pushUse.ownerId != decision.id
					|| pushUse.requirementId != runtimeRequirementId
					|| pushUse.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
					|| pushUse.exactSymbol != "HxArray.push"
					|| pushUse.role != 'store-element:$index'
					|| pushUse.order != storeStep.ordinal
					|| pushUse.cardinality != 1) {
					Context.error('Array literal producer case "$name" has an invalid HxArray.push occurrence for element $index.', field.pos);
				}
			}
			decisions.push(decision);
		}

		for (name in ["bools", "nested"])
			if (new OcamlArrayLiteralProducerPlanner(binding(name), representations).plan(fieldBody(requiredField(fields, name))).decisions().length != 0)
				Context.error('Unsupported array literal case "$name" was admitted by the direct Int/String producer.', requiredField(fields, name).pos);

		final stringBody = fieldBody(requiredField(fields, "strings"));
		final stringLiteral = firstLiteral(stringBody);
		if (stringLiteral == null)
			Context.error("The strings case has no typed array literal.", Context.currentPos());
		final stringNormalized = OcamlDirectArraySourceIdentity.normalize(stringLiteral.t);
		if (stringNormalized == null
			|| stringNormalized.elementSemanticTypeId != "String"
			|| OcamlRepresentationRegistry.normalizedDirectFlatArray(stringLiteral.t) != null
			|| !OcamlArrayLiteralProducerPlan.isAdmittedLiteral(stringLiteral)) {
			Context.error("The String literal was not admitted through its producer-only source identity.", stringLiteral.pos);
		}
		final stringPlanner = new OcamlArrayLiteralProducerPlanner(binding("strings"), representations);
		final firstStringPlan = stringPlanner.plan(stringBody);
		final secondStringPlan = stringPlanner.plan(stringBody);
		final firstStringDecision = firstStringPlan.decisions()[0];
		final secondStringDecision = secondStringPlan.decisions()[0];
		final expectedStringDecision = directStringDecision(stringLiteral, binding("strings"), representations);
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
			Context.error("The active String producer disagrees with its independently authored descriptor and construction contract.", stringLiteral.pos);
		}
		switch (firstStringPlan.syntaxLookup(stringLiteral)) {
			case OcamlArrayLiteralProducerLookup.Required(decision) if (decision.id == firstStringDecision.id):
			case _:
				Context.error("The active String producer is not reachable through its exact request-local typed occurrence.", stringLiteral.pos);
		}
		if (firstStringPlan.requireFor(stringLiteral, representations).id != firstStringDecision.id)
			Context.error("The active String producer failed its final representation-graph check.", stringLiteral.pos);

		expectThrows("stale-representation",
			() -> new OcamlArrayLiteralProducerPlanner(changedProgramBinding("strings"), representations).plan(fieldBody(requiredField(fields, "strings"))));
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

		final missingRequirement = copy(sample, {runtimeRequirementIds: []});
		expectThrows("invalid-runtime-requirement", () -> new OcamlArrayLiteralProducerPlan([missingRequirement]));
		final missingRuntimeUse = copy(sample, {runtimeUseOccurrences: sample.runtimeUseOccurrences.slice(0, sample.runtimeUseOccurrences.length - 1)});
		expectThrows("invalid-runtime-use", () -> new OcamlArrayLiteralProducerPlan([missingRuntimeUse]));
		final duplicatedRuntimeUse = copy(sample, {runtimeUseOccurrences: [sample.runtimeUseOccurrences[0]].concat(sample.runtimeUseOccurrences)});
		expectThrows("invalid-runtime-use", () -> new OcamlArrayLiteralProducerPlan([duplicatedRuntimeUse]));
		final reorderedRuntimeUses = sample.runtimeUseOccurrences.copy();
		final reorderedRuntimeUse = reorderedRuntimeUses[0];
		reorderedRuntimeUses[0] = reorderedRuntimeUses[1];
		reorderedRuntimeUses[1] = reorderedRuntimeUse;
		expectThrows("invalid-runtime-use", () -> new OcamlArrayLiteralProducerPlan([copy(sample, {runtimeUseOccurrences: reorderedRuntimeUses})]));
		final wrongRuntimeSymbol = copy(sample, {});
		Reflect.setField(cast wrongRuntimeSymbol.runtimeUseOccurrences[0], "exactSymbol", "HxArray.push");
		expectThrows("invalid-runtime-use", () -> new OcamlArrayLiteralProducerPlan([wrongRuntimeSymbol]));
		final staleRuntimeUse = copy(sample, {});
		Reflect.setField(cast staleRuntimeUse.runtimeUseOccurrences[0], "planRevision", changedRevision());
		expectThrows("invalid-runtime-use", () -> new OcamlArrayLiteralProducerPlan([staleRuntimeUse]));
		final wrongRuntimeProfile = copy(sample, {});
		Reflect.setField(cast wrongRuntimeProfile.runtimeUseOccurrences[0], "profileEligibility", ["portable"]);
		expectThrows("invalid-runtime-use", () -> new OcamlArrayLiteralProducerPlan([wrongRuntimeProfile]));

		proveRuntimeSyntax(sample, sampleLiteral);

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
		Builds the independent expected record for one active String literal.

		This manually assembled value keeps the expected carrier, descriptor, element,
		and schedule independent from the planner that is being tested.
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
		final evaluationSchedule = OcamlArrayLiteralProducerContract.schedule(elements);
		final runtimeRequirementId = id + ":runtime:haxe-array-literal-construction";
		final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(owner);
		final runtimeUseOccurrences = [
			{
				id: id + ":runtime-use:create",
				planRevision: runtimePlanRevision,
				ownerId: id,
				requirementId: runtimeRequirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: "HxArray.create",
				role: "create-array",
				order: 0,
				source: source,
				profileEligibility: ["metal", "portable"],
				cardinality: 1
			}
		];
		for (index in 0...elements.length) {
			runtimeUseOccurrences.push({
				id: id + ':runtime-use:push:$index',
				planRevision: runtimePlanRevision,
				ownerId: id,
				requirementId: runtimeRequirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: "HxArray.push",
				role: 'store-element:$index',
				order: index * 2 + 2,
				source: elements[index].source,
				profileEligibility: ["metal", "portable"],
				cardinality: 1
			});
		}
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
			evaluationSchedule: evaluationSchedule,
			constructionPolicy: "create-then-evaluate-and-push-in-order",
			proofId: "direct-array-string-literal-construction-v1",
			proofClaim: "This occurrence allocates one direct represented Array<String>, evaluates each exact String element once in increasing source order, stores each evaluated carrier once, and returns the same mutable HxArray object. The claim ends at literal construction and does not admit another array shape, element family, call, return, field, typed catch, or public/native boundary.",
			profileEligibility: ["metal", "portable"],
			runtimeRequirementIds: [runtimeRequirementId],
			runtimeUseOccurrences: runtimeUseOccurrences,
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

	/**
		Checks that syntax consumes the sealed uses and that structural corruption fails.

		The fixture supplies inert element expressions because this proof owns only
		the container create and push calls. The portable fixtures separately execute
		real source elements and check their evaluation order.
	**/
	static function proveRuntimeSyntax(decision:OcamlArrayLiteralProducerDecision, literal:TypedExpr):Void {
		final items = switch (literal.expr) {
			case TArrayDecl(values): values;
			case _: Context.error("The runtime-use syntax proof requires a typed array literal.", literal.pos);
		};
		final requirements = OcamlRuntimeRequirementLedger.requirementsForArrayLiteralProducer(decision);
		if (requirements.length != 1
			|| requirements[0].id != decision.runtimeRequirementIds[0]
			|| requirements[0].rootModules.join(",") != "HxArray") {
			Context.error("The array-literal runtime requirement does not select the exact HxArray root.", literal.pos);
		}

		function materialize(authority:OcamlRuntimeUseAuthority) {
			var temporaryIndex = 0;
			return OcamlArrayLiteralSyntax.build(decision, items, _ -> OcamlExpr.EConst(OcamlConst.CInt(0)), prefix -> {
				temporaryIndex += 1;
				return prefix + "_fixture_" + temporaryIndex;
			}, authority);
		}

		function authority(?occurrences:Array<OcamlRuntimeUseOccurrence>):OcamlRuntimeUseAuthority {
			return new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(binding("ordered")), "portable", requirements,
				occurrences == null ? decision.runtimeUseOccurrences : occurrences);
		}

		final validAuthority = authority();
		final valid = materialize(validAuthority);
		validAuthority.reconcileExpression(OcamlExpr.ESeq(valid.runtimeOperations));
		final receipts = validAuthority.receiptsSorted();
		if (receipts.length != decision.runtimeUseOccurrences.length
			|| receipts[0].exactSymbol != "HxArray.create"
			|| receipts[receipts.length - 1].exactSymbol != "HxArray.push") {
			Context.error("The array-literal syntax did not consume its planned runtime uses in order.", literal.pos);
		}
		expectThrows("after reconciliation",
			() -> validAuthority.expressionIdentifier(decision.runtimeUseOccurrences[0].id, decision.runtimeUseOccurrences[0].planRevision,
				decision.runtimeUseOccurrences[0].exactSymbol));

		final missingAuthority = authority();
		final missing = materialize(missingAuthority);
		expectThrows("missing runtime use", () -> missingAuthority.reconcileExpression(OcamlExpr.ESeq(missing.runtimeOperations.slice(1))));

		final duplicateAuthority = authority();
		final duplicate = materialize(duplicateAuthority);
		final duplicateOperations = duplicate.runtimeOperations.copy();
		duplicateOperations.push(duplicate.runtimeOperations[duplicate.runtimeOperations.length - 1]);
		expectThrows("duplicate runtime use", () -> duplicateAuthority.reconcileExpression(OcamlExpr.ESeq(duplicateOperations)));

		final reorderedAuthority = authority();
		final reordered = materialize(reorderedAuthority);
		final reorderedOperations = reordered.runtimeOperations.copy();
		final firstOperation = reorderedOperations[0];
		reorderedOperations[0] = reorderedOperations[1];
		reorderedOperations[1] = firstOperation;
		expectThrows("runtime use order", () -> reorderedAuthority.reconcileExpression(OcamlExpr.ESeq(reorderedOperations)));

		final plainAuthority = authority();
		final plainCreate = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "create"), [OcamlExpr.EConst(OcamlConst.CUnit)]);
		expectThrows("plain private runtime reference HxArray.create", () -> plainAuthority.reconcileExpression(plainCreate));

		final profileOccurrences = decision.runtimeUseOccurrences.map(use -> {
			id: use.id,
			planRevision: use.planRevision,
			ownerId: use.ownerId,
			requirementId: use.requirementId,
			domain: use.domain,
			exactSymbol: use.exactSymbol,
			role: use.role,
			order: use.order,
			source: use.source,
			profileEligibility: ["metal"],
			cardinality: use.cardinality
		});
		expectThrows("not eligible for profile portable", () -> materialize(authority(profileOccurrences)));
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
