import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPlanner;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Metadata and parentheses must not turn a direct return into a private runtime signal. */
class ControlRootFixture {
	static function metadata(expression:TypedExpr):TypedExpr {
		return {
			expr: TMeta({name: ":controlRootFixture", params: [], pos: expression.pos}, expression),
			pos: expression.pos,
			t: expression.t
		};
	}

	static function parentheses(expression:TypedExpr):TypedExpr {
		return {expr: TParenthesis(expression), pos: expression.pos, t: expression.t};
	}

	/** Keep exact return nodes so the test can check their occurrence ownership. */
	static function check(label:String, source:TypedExpr, body:TypedExpr, expected:Array<TypedExpr>):Void {
		final original = switch (source.expr) {
			case TFunction(value): value;
			case _: throw "control root fixture requires a typed function";
		};
		final functionBody:TFunc = {args: original.args, t: original.t, expr: body};
		final functionExpression:TypedExpr = {expr: TFunction(functionBody), t: source.t, pos: source.pos};
		final binding:OcamlFunctionPlanBinding = {
			functionId: "control-root:" + label,
			programRevision: "program:control-root-fixture",
			bodyRevision: haxe.crypto.Sha256.encode(TypedExprTools.toString(functionExpression)),
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(binding.programRevision);
		final callable = new OcamlCallPlanner(representations, binding).boundaryForNestedRepresentedResult(functionBody);
		if (callable == null)
			throw label + ": missing represented result";
		final identities = LexicalLocalIdentityPlan.build(binding.functionId, functionExpression);
		final controls = new OcamlControlPlanner(representations, new OcamlLocalRepresentationPlan([]), binding,
			identities).plan(body, OcamlFunctionResultBoundary.fromCallable(callable));
		if (controls.decisions().length != expected.length)
			throw label + ": expected " + expected.length + " non-local returns, got " + controls.decisions().length;
		for (expression in expected)
			if (controls.decisionFor(expression) == null)
				throw label + ": non-local return lost exact node ownership";
	}

	/** Checks that structural wrappers preserve direct returns and exact early-return ownership. */
	public static function checkAll():Void {
		final source = Context.typeExpr(macro function(flag:Bool):String {
			if (flag)
				return "early";
			return "tail";
		});
		final body = switch (source.expr) {
			case TFunction(value): value.expr;
			case _: throw "control root fixture requires a typed function";
		};
		final returns = new Array<TypedExpr>();
		function collect(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TReturn(_):
					returns.push(expression);
				case _:
					TypedExprTools.iter(expression, collect);
			}
		}
		collect(body);
		if (returns.length != 2)
			throw "control root fixture requires one early and one direct return";
		check("plain", source, body, [returns[0]]);
		check("metadata-root", source, metadata(body), [returns[0]]);
		check("parenthesized-root", source, parentheses(body), [returns[0]]);
		check("mixed-root", source, metadata(parentheses(metadata(body))), [returns[0]]);
		final wrappedStatements:TypedExpr = switch (body.expr) {
			case TBlock(expressions):
				{expr: TBlock(expressions.map(expression -> metadata(parentheses(expression)))), pos: body.pos, t: body.t};
			case _: throw "control root fixture requires a block";
		};
		check("wrapped-statements", source, wrappedStatements, [returns[0]]);
		check("direct-root", source, returns[1], []);
		check("wrapped-direct-root", source, metadata(parentheses(returns[1])), []);
		Sys.println("OCAML_CONTROL_ROOT_TRANSPARENCY:PASS");
	}

	public static macro function run():Expr {
		checkAll();
		return macro null;
	}
}
