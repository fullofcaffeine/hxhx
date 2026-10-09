import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlMapEqualityBuilder.build;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlMapIdentityPlan;
import reflaxe.ocaml.lowered.OcamlMapIdentityPlan.OcamlMapIdentityPlanner;

/** Checks request isolation and rejection before syntax callbacks can run. */
class MapIdentityFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "map-comparison",
		programRevision: "program-1",
		bodyRevision: "body-1",
		pipelineRevision: "pipeline-1"
	};

	public static macro function run():Expr {
		final root = Context.typeExpr(macro {
			final value:Map<Int, String> = [1 => "same"];
			final nullable:Null<Map<Int, String>> = value;
			nullable == value;
			value != nullable;
			final nested = () -> nullable == value;
			// Deliberate foreign boundary: it must retain the Dynamic equality owner.
			final foreign:Dynamic = value;
			foreign == value;
			1 == 2;
		});
		final comparisons:Array<TypedExpr> = [];
		function collect(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TBinop(OpEq | OpNotEq, _, _):
					comparisons.push(expression);
				case _:
			}
			TypedExprTools.iter(expression, collect);
		}
		collect(root);
		if (comparisons.length != 5)
			throw "Expected two outer Map comparisons, one nested, Dynamic, and scalar";
		final plan = new OcamlMapIdentityPlanner(binding).plan(root);
		if (plan.requireFor(comparisons[0]).negate || !plan.requireFor(comparisons[1]).negate)
			throw "Equality operator was lost";
		for (excluded in comparisons.slice(2))
			expectFailure("map-equality:missing", () -> plan.requireFor(excluded));
		new OcamlMapIdentityPlanner(binding).plan(comparisons[2]).requireFor(comparisons[2]);
		final changedBinding:OcamlFunctionPlanBinding = {
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: "body-2",
			pipelineRevision: binding.pipelineRevision
		};
		expectFailure("map-equality:stale", () -> plan.requirePlanBinding(changedBinding));
		final expression = comparisons[0];
		final decision = plan.requireFor(expression);
		if (decision.binding == binding || decision.binding == plan.requireFor(expression).binding)
			throw "Inspection exposed mutable request binding storage";
		expectFailure("map-equality:duplicate", () -> new OcamlMapIdentityPlan([
			{expression: expression, decision: decision},
			{expression: expression, decision: decision}
		]));
		var builds = 0;
		var temporaries = 0;
		function render(activeBinding:OcamlFunctionPlanBinding):OcamlExpr {
			return build({
				plan: plan,
				binding: activeBinding,
				expression: expression,
				buildExpr: _ -> {
					builds++;
					return EIdent("operand");
				},
				freshTmp: prefix -> prefix + temporaries++
			});
		}
		expectFailure("map-equality:operand", () -> render(changedBinding));
		final original = expression.expr;
		switch (original) {
			case TBinop(_, left, right):
				expression.expr = TBinop(OpNotEq, left, right);
			case _:
				throw "Expected comparison";
		}
		expectFailure("map-equality:operand", () -> render(binding));
		expression.expr = original;
		if (builds != 0 || temporaries != 0)
			throw "Rejected comparison invoked syntax callbacks";
		final rendered = render(binding);
		switch (rendered) {
			case ELet(_, _, ELet(_, _, EBinop(PhysEq, _, _), false), false):
			case _:
				throw "Map identity must bind both operands before physical equality";
		}
		if (builds != 2 || temporaries != 2)
			throw "Accepted comparison did not build each operand exactly once";
		Sys.println("REFLAXE_OCAML_MAP_IDENTITY:PASS");
		return macro null;
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
