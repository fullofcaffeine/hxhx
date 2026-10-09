import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlEnumIdentityPlan;
import reflaxe.ocaml.lowered.OcamlEnumIdentityPlan.OcamlEnumEqualityDecision;
import reflaxe.ocaml.lowered.OcamlEnumIdentityPlan.OcamlEnumAllocationDecision;
import reflaxe.ocaml.lowered.OcamlEnumIdentityPlan.OcamlEnumIdentityPlanner;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/** Independently checks selection, request identity, copied facts, and exact helper ownership. */
class EnumEqualityFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "enum-comparison-test",
		programRevision: "program-1",
		bodyRevision: "body-1",
		pipelineRevision: "pipeline-1"
	};

	public static macro function run():Expr {
		final root = Context.typeExpr(macro {
			final value:Null<Signal> = Signal.Ready;
			value == Signal.Ready;
			Signal.Ready != value;
			value == null;
			final nested = () -> value == Signal.Ready;
			// This explicit input tests exclusion of the Dynamic comparison boundary.
			final dynamicValue:Dynamic = value;
			dynamicValue == value;
			"same" == "same";
			1 != 2;
		});
		final plan = new OcamlEnumIdentityPlanner(binding).plan(root);
		final decisions = plan.decisions();
		if (decisions.length != 2 || decisions[0].negate || !decisions[1].negate)
			throw "Expected exactly the two outer enum comparisons";
		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(binding.programRevision);
		plan.recordRequirements(ledger);
		for (decision in decisions) {
			if (decision.enumName != "Signal")
				throw "The comparison lost its enum identity";
			final uses = OcamlEnumIdentityPlan.runtimeUses(decision);
			if (uses.length != 2
				|| uses[0].exactSymbol != "HxEnum.unbox_or_obj"
				|| uses[1].exactSymbol != "HxEnum.unbox_or_obj"
				|| uses[0].role != "left-enum-value"
				|| uses[1].role != "right-enum-value")
				throw "Each operand must own one existing enum recovery helper";
			final requirements = ledger.requirementsByIds([OcamlEnumIdentityPlan.requirementId(decision)]);
			if (requirements.length != 1 || requirements[0].rootModules.join(",") != "HxEnum")
				throw "The enum helper has no exact packaging requirement";
			final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, uses);
			final references = [
				for (use in uses)
					OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol))
			];
			authority.reconcileExpression(OcamlExpr.ESeq(references));
			expectFailure("missing runtime use",
				() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, uses).reconcileExpression(OcamlExpr.ESeq([references[0]])));
			expectFailure("wrong target symbol",
				() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
					uses).expressionIdentifier(uses[0].id, uses[0].planRevision, "HxEnum.box_if_needed"));
			for (changed in [
				alter(decision, "WrongSignal", decision.negate),
				alter(decision, decision.enumName, !decision.negate)
			])
				expectFailure("enum-equality:invalid", () -> OcamlEnumIdentityPlan.requireDecision(changed));
		}
		expectFailure("enum-equality:stale", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: "changed-body",
			pipelineRevision: binding.pipelineRevision
		}));
		expectFailure("enum-equality:missing", () -> plan.requireFor(Context.typeExpr(macro Signal.Ready == Signal.Ready)));
		decisions[0] = alter(decisions[0], "ChangedCopy", false);
		plan.requirePlanBinding(binding);
		OcamlEnumIdentityPlan.requireDecision(plan.decisions()[0]);
		final constructor = Context.typeExpr(macro Signal.Value(7));
		final constructionPlan = new OcamlEnumIdentityPlanner(binding).plan(constructor);
		final allocation = constructionPlan.requireAllocation(constructor);
		if (allocation.enumName != "Signal" || allocation.constructorName != "Value" || allocation.arity != 1)
			throw "Payload construction lost its exact enum, constructor, or argument count";
		final changedAllocation:OcamlEnumAllocationDecision = {
			binding: allocation.binding,
			source: allocation.source,
			enumName: allocation.enumName,
			constructorName: allocation.constructorName,
			arity: 2,
			revision: allocation.revision
		};
		expectFailure("enum-allocation:invalid", () -> OcamlEnumIdentityPlan.requireAllocationDecision(changedAllocation));
		expectFailure("enum-allocation:missing", () -> constructionPlan.requireAllocation(Context.typeExpr(macro Signal.Value(7))));
		expectFailure("enum-allocation:stale", () -> constructionPlan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: "changed-program",
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		}));
		Sys.println("REFLAXE_OCAML_ENUM_EQUALITY:PASS");
		return macro null;
	}

	static function alter(value:OcamlEnumEqualityDecision, name:String, negate:Bool):OcamlEnumEqualityDecision {
		return {
			id: value.id,
			revision: value.revision,
			binding: value.binding,
			source: value.source,
			enumName: name,
			leftType: value.leftType,
			rightType: value.rightType,
			negate: negate,
			order: value.order
		};
	}

	static function expectFailure(fragment:String, action:() -> Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(fragment) >= 0)
				return;
			throw error;
		}
		throw "Expected rejection containing " + fragment;
	}
}
