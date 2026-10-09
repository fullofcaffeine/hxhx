import haxe.macro.Context;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Initializer call inventories must match their source root and current request. */
class StandaloneCallPlanChecks {
	public static function run():Void {
		final registry = new OcamlFunctionPlanRegistry();
		final representations = new OcamlRepresentationRegistry();
		registry.beginProgram("program:standalone-call-checks");
		representations.beginProgram("program:standalone-call-checks");
		final expression = Context.typeExpr(macro {
			final values:Array<Int> = [];
			values.push(7);
		});
		final changed = Context.typeExpr(macro {
			final values:Array<Int> = [];
			values.push(8);
		});
		final plan = registry.sealStandaloneExpression("field:values", expression, representations);
		final calls = plan.calls.decisions();
		if (calls.length != 1
			|| calls[0].standardArrayTarget == null
			|| calls[0].standardArrayTarget.operation != "push"
			|| plan.calls.runtimeUsePlanFor(calls[0].id) == null
			|| registry.callDecisions().length != 1)
			throw "standalone push lost its call or runtime inventory";
		registry.requireStandaloneExpressionPlan(expression, plan, representations);
		reject("stale-standalone-plan", () -> registry.requireStandaloneExpressionPlan(changed, plan, representations));
		registry.sealStandaloneExpression("field:values", changed, representations);
		reject("missing-standalone-inventory", () -> registry.requireStandaloneExpressionPlan(expression, plan, representations));
		registry.beginProgram("program:standalone-call-checks");
		if (registry.callDecisions().length != 0)
			throw "standalone calls leaked across compilation requests";
		reject("missing-standalone-inventory", () -> registry.requireStandaloneExpressionPlan(expression, plan, representations));
	}

	static function reject(code:String, operation:Void->Void):Void {
		try {
			operation();
		} catch (error:String) {
			if (error.indexOf(code) < 0)
				throw error;
			return;
		}
		throw "expected standalone call rejection: " + code;
	}
}
