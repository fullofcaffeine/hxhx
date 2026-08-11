package;

import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Checks the sealed call and private-helper schedule for Dynamic functions. */
class DynamicFunctionCallFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "DynamicFunctionCallFixture.main",
		programRevision: "program:dynamic-function-call",
		bodyRevision: "body:dynamic-function-call",
		pipelineRevision: "pipeline:dynamic-function-call"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final pair:Dynamic = function(left:Int, right:Int):Int return left + right;
			pair(1, 2);
			final zero:Dynamic = function():Int return 7;
			zero();
		});
		final plan = new OcamlCallPlanner(new OcamlRepresentationRegistry(), binding).plan(typed);
		final decisions = plan.decisions().filter(decision -> decision.kind == OcamlCallKind.DynamicFunctionValue);
		if (decisions.length != 2)
			throw 'Expected two sealed Dynamic function calls, received ${decisions.length}.';

		for (decision in decisions) {
			final target = decision.dynamicFunctionTarget;
			if (target == null)
				throw 'Dynamic call "${decision.id}" has no sealed target.';
			final runtimeUses = plan.runtimeUsePlanFor(decision.id);
			if (runtimeUses == null)
				throw 'Dynamic call "${decision.id}" has no private-runtime schedule.';
			OcamlCallRuntimeUseContract.requireForCall(decision, runtimeUses);
			final expectedRoles = ["dynamic-call-argument-array-create"];
			for (index in 0...target.argumentSemanticTypeIds.length)
				expectedRoles.push('dynamic-call-argument-push:$index');
			expectedRoles.push("dynamic-call-invoke");
			expectedRoles.push("dynamic-call-null-receiver");
			final actualRoles = runtimeUses.runtimeUseOccurrences.map(occurrence -> occurrence.role);
			if (actualRoles.join(",") != expectedRoles.join(","))
				throw 'Dynamic call "${decision.id}" has runtime order ${actualRoles.join(",")}, expected ${expectedRoles.join(",")}.';
		}

		Sys.println("REFLAXE_OCAML_DYNAMIC_FUNCTION_CALL:PASS");
		return macro null;
	}
}
