package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadContract;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadDecision;
import reflaxe.ocaml.lowered.OcamlArrayReadPlan;
import reflaxe.ocaml.lowered.OcamlArrayReadPlan.OcamlArrayReadPlanner;
import reflaxe.ocaml.lowered.OcamlDynamicBracketReadModel.OcamlDynamicBracketReadDecision;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/**
	Checks the decision that owns one standard Array bracket read.

	The planner distinguishes a value read from the same syntax used as an
	assignment or update target. The runtime check then proves that syntax can use
	only the one `HxArray.get` identifier selected by that decision.
**/
class ArrayReadPlanFixture {
	static inline final PROGRAM_REVISION = "program:array-read-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final fields = caseFields();
		final orderedBody = fieldBody(requiredField(fields, "ordered"));
		final owner = binding("ordered");
		final first = new OcamlArrayReadPlanner(owner).plan(orderedBody);
		final second = new OcamlArrayReadPlanner(owner).plan(orderedBody);
		if (first.revision != second.revision)
			Context.error("The Array-read plan revision is not deterministic.", orderedBody.pos);
		final decisions = first.decisions();
		if (decisions.length != 1)
			Context.error('The ordered case expected one Array read, received ${decisions.length}.', orderedBody.pos);
		final decision = decisions[0];
		final read = firstArrayRead(orderedBody);
		if (read == null || first.requireFor(read).id != decision.id)
			Context.error("The ordered case did not resolve its exact typed Array read.", orderedBody.pos);
		if (decision.readOrdinal != 0
			|| decision.receiverSemanticTypeId != "Array<Int>"
			|| decision.elementSemanticTypeId != "Int"
			|| decision.indexSemanticTypeId != "Int"
			|| decision.resultSemanticTypeId != "Int"
			|| decision.evaluationOrder.join(",") != "receiver,index,runtime-read"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.functionId != owner.functionId
			|| decision.programRevision != owner.programRevision
			|| decision.bodyRevision != owner.bodyRevision
			|| decision.pipelineRevision != owner.pipelineRevision) {
			Context.error("The ordered case disagrees with the Array-read contract.", orderedBody.pos);
		}
		final use = decision.runtimeUseOccurrences[0];
		if (use.id != decision.id + ":runtime-use:get"
			|| use.planRevision != OcamlRuntimeUseModel.planRevision(owner)
			|| use.ownerId != decision.id
			|| use.requirementId != decision.runtimeRequirementIds[0]
			|| use.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| use.exactSymbol != "HxArray.get"
			|| use.role != "read-element"
			|| use.order != 0
			|| use.profileEligibility.join(",") != "metal,portable"
			|| use.cardinality != 1) {
			Context.error("The ordered case has an invalid HxArray.get occurrence.", orderedBody.pos);
		}

		assertReadCount(fields, "assignmentTarget", 1);
		assertReadCount(fields, "updateTarget", 1);
		proveDynamicRead(fields);

		expectThrows("duplicate-decision", () -> new OcamlArrayReadPlan([decision, decision]));
		expectThrows("stale-plan", () -> new OcamlArrayReadPlan([decision]).requirePlanBinding({
			functionId: owner.functionId,
			programRevision: owner.programRevision,
			bodyRevision: owner.bodyRevision + ":changed",
			pipelineRevision: owner.pipelineRevision
		}));
		expectThrows("missing-decision", () -> new OcamlArrayReadPlan([]).requireFor(read));
		expectThrows("invalid-decision", () -> new OcamlArrayReadPlan([copyWith(decision, [], decision.runtimeUseOccurrences)]));
		expectThrows("invalid-runtime-use", () -> new OcamlArrayReadPlan([
			copyWith(decision, decision.runtimeRequirementIds, [
				copyUse(use, "HxArray.set", use.planRevision, use.ownerId, use.order, use.profileEligibility)
			])
		]));
		expectThrows("invalid-runtime-use", () -> new OcamlArrayReadPlan([
			copyWith(decision, decision.runtimeRequirementIds, [
				copyUse(use, use.exactSymbol, changedRevision(), use.ownerId, use.order, use.profileEligibility)
			])
		]));
		expectThrows("invalid-runtime-use", () -> new OcamlArrayReadPlan([
			copyWith(decision, decision.runtimeRequirementIds, [
				copyUse(use, use.exactSymbol, use.planRevision, "wrong-owner", use.order, use.profileEligibility)
			])
		]));
		expectThrows("invalid-runtime-use", () -> new OcamlArrayReadPlan([
			copyWith(decision, decision.runtimeRequirementIds, [
				copyUse(use, use.exactSymbol, use.planRevision, use.ownerId, 1, use.profileEligibility)
			])
		]));
		expectThrows("invalid-runtime-use", () -> new OcamlArrayReadPlan([
			copyWith(decision, decision.runtimeRequirementIds, [
				copyUse(use, use.exactSymbol, use.planRevision, use.ownerId, use.order, ["portable"])
			])
		]));

		proveRuntimeAuthority(decision, owner);
		Sys.println("REFLAXE_OCAML_ARRAY_READ_PLAN_FIXTURE:PASS");
		return macro null;
	}

	static function proveDynamicRead(fields:Map<String, ClassField>):Void {
		final body = fieldBody(requiredField(fields, "dynamicRead"));
		final owner = binding("dynamicRead");
		final plan = new OcamlArrayReadPlanner(owner).plan(body);
		final decisions = plan.dynamicDecisions();
		final read = firstDynamicRead(body);
		if (decisions.length != 1 || read == null || plan.requireDynamicFor(read).id != decisions[0].id)
			Context.error("The Dynamic bracket case did not resolve one exact compatibility decision.", body.pos);
		final decision = decisions[0];
		final use = decision.runtimeUseOccurrences[0];
		final requirements = OcamlRuntimeRequirementLedger.requirementsForDynamicBracketRead(decision);
		final authority = new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(owner), "portable", requirements, decision.runtimeUseOccurrences);
		authority.reconcileExpression(OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol)));
		if (authority.receiptsSorted().length != 1)
			Context.error("The Dynamic bracket decision did not consume its exact runtime occurrence.", body.pos);

		expectThrows("missing-decision", () -> new OcamlArrayReadPlan([]).requireDynamicFor(read));
		expectThrows("stale-plan", () -> new OcamlArrayReadPlan([], null, [decision]).requirePlanBinding({
			functionId: owner.functionId,
			programRevision: owner.programRevision,
			bodyRevision: owner.bodyRevision + ":changed",
			pipelineRevision: owner.pipelineRevision
		}));
		expectThrows("invalid-runtime-use", () -> new OcamlArrayReadPlan([], null, [
			copyDynamicWithUse(decision, copyUse(use, "HxArray.set", use.planRevision, use.ownerId, use.order, use.profileEligibility))
		]));
		final plainAuthority = new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(owner), "portable", requirements, decision.runtimeUseOccurrences);
		expectThrows("plain private runtime reference HxArray.get",
			() -> plainAuthority.reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get")));
	}

	static function assertReadCount(fields:Map<String, ClassField>, name:String, expected:Int):Void {
		final body = fieldBody(requiredField(fields, name));
		final actual = new OcamlArrayReadPlanner(binding(name)).plan(body).decisions().length;
		if (actual != expected)
			Context.error('Array-read case "$name" expected $expected value read, received $actual. Assignment and update targets must not become separate reads.',
				body.pos);
	}

	static function proveRuntimeAuthority(decision:OcamlArrayReadDecision, owner:OcamlFunctionPlanBinding):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForArrayRead(decision);
		if (requirements.length != 1
			|| requirements[0].id != decision.runtimeRequirementIds[0]
			|| requirements[0].rootModules.join(",") != "HxArray") {
			Context.error("The Array-read requirement does not select the exact HxArray root.", Context.currentPos());
		}
		final use = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(owner), "portable", requirements, decision.runtimeUseOccurrences);
		final checked = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
		authority.reconcileExpression(checked);
		if (authority.receiptsSorted().length != 1)
			Context.error("The valid Array read did not consume one runtime occurrence.", Context.currentPos());

		final plainAuthority = new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(owner), "portable", requirements, decision.runtimeUseOccurrences);
		final plain = OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "get");
		expectThrows("plain private runtime reference HxArray.get", () -> plainAuthority.reconcileExpression(plain));

		final missingAuthority = new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(owner), "portable", requirements,
			decision.runtimeUseOccurrences);
		expectThrows("missing runtime use", () -> missingAuthority.reconcileExpression(OcamlExpr.EConst(reflaxe.ocaml.ast.OcamlConst.CUnit)));
	}

	static function copyWith(decision:OcamlArrayReadDecision, requirementIds:Array<String>, uses:Array<OcamlRuntimeUseOccurrence>):OcamlArrayReadDecision {
		final copy = OcamlArrayReadPlan.copyDecision(decision);
		return {
			id: copy.id,
			source: copy.source,
			readOrdinal: copy.readOrdinal,
			receiverSemanticTypeId: copy.receiverSemanticTypeId,
			elementSemanticTypeId: copy.elementSemanticTypeId,
			indexSemanticTypeId: copy.indexSemanticTypeId,
			resultSemanticTypeId: copy.resultSemanticTypeId,
			evaluationOrder: copy.evaluationOrder,
			profileEligibility: copy.profileEligibility,
			runtimeRequirementIds: requirementIds,
			runtimeUseOccurrences: uses,
			proofId: copy.proofId,
			proofClaim: copy.proofClaim,
			functionId: copy.functionId,
			programRevision: copy.programRevision,
			bodyRevision: copy.bodyRevision,
			pipelineRevision: copy.pipelineRevision
		};
	}

	static function copyUse(use:OcamlRuntimeUseOccurrence, exactSymbol:String, planRevision:String, ownerId:String, order:Int,
			profileEligibility:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: use.id,
			planRevision: planRevision,
			ownerId: ownerId,
			requirementId: use.requirementId,
			domain: use.domain,
			exactSymbol: exactSymbol,
			role: use.role,
			order: order,
			source: use.source,
			profileEligibility: profileEligibility,
			cardinality: use.cardinality
		};
	}

	static function copyDynamicWithUse(decision:OcamlDynamicBracketReadDecision, use:OcamlRuntimeUseOccurrence):OcamlDynamicBracketReadDecision {
		final copy = OcamlArrayReadPlan.copyDynamicDecision(decision);
		return {
			id: copy.id,
			source: copy.source,
			readOrdinal: copy.readOrdinal,
			receiverSemanticTypeId: copy.receiverSemanticTypeId,
			indexSemanticTypeId: copy.indexSemanticTypeId,
			resultSemanticTypeId: copy.resultSemanticTypeId,
			evaluationOrder: copy.evaluationOrder,
			profileEligibility: copy.profileEligibility,
			runtimeRequirementIds: copy.runtimeRequirementIds,
			runtimeUseOccurrences: [use],
			proofId: copy.proofId,
			proofClaim: copy.proofClaim,
			functionId: copy.functionId,
			programRevision: copy.programRevision,
			bodyRevision: copy.bodyRevision,
			pipelineRevision: copy.pipelineRevision
		};
	}

	static function binding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "ArrayReadCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: "body:array-read-fixture:" + name,
			pipelineRevision: "pipeline:array-read-fixture"
		};
	}

	static function firstArrayRead(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			if (OcamlArrayReadPlan.admittedOccurrence(expression) != null) {
				found = expression;
				return;
			}
			switch (expression.expr) {
				case TFunction(_):
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}
		visit(body);
		return found;
	}

	static function firstDynamicRead(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			if (OcamlArrayReadPlan.admittedDynamicOccurrence(expression) != null) {
				found = expression;
				return;
			}
			switch (expression.expr) {
				case TFunction(_):
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}
		visit(body);
		return found;
	}

	static function requiredField(fields:Map<String, ClassField>, name:String):ClassField {
		final field = fields.get(name);
		if (field == null)
			Context.error('Missing typed Array-read case "$name".', Context.currentPos());
		return field;
	}

	static function fieldBody(field:ClassField):TypedExpr {
		final expression = field.expr();
		if (expression == null)
			Context.error('Array-read case "${field.name}" has no typed body.', field.pos);
		return switch (expression.expr) {
			case TFunction(tfunc): tfunc.expr;
			case _: expression;
		};
	}

	static function changedRevision():String {
		return "sha256:" + StringTools.lpad("", "0", 64);
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
		return switch (Context.getType("ArrayReadCases")) {
			case TInst(classRef, _): [for (field in classRef.get().statics.get()) field.name => field];
			case _: Context.error("ArrayReadCases did not resolve to a class.", Context.currentPos());
		};
	}
}
