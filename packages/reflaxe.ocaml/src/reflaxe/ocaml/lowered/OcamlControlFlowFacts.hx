package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;

/**
	Conservative structural facts about function-local Haxe control flow.

	These checks do not infer enum exhaustiveness, loop termination, dominance,
	or reachability. They only recognize final typed-tree shapes whose every
	visible branch ends in an explicit source-level transfer. Call planning uses
	the narrower return-only fact; catch lowering also admits explicit throws
	because both transfers remain target-polymorphic in generated OCaml.
**/
class OcamlControlFlowFacts {
	/** Whether every structurally visible path ends in an explicit Haxe return. */
	public static function definitelyReturns(expression:TypedExpr):Bool {
		return definitelyTransfers(expression, false);
	}

	/** Whether every structurally visible path ends in an explicit return or throw. */
	public static function definitelyReturnsOrThrows(expression:TypedExpr):Bool {
		return definitelyTransfers(expression, true);
	}

	static function definitelyTransfers(expression:TypedExpr, allowThrow:Bool):Bool {
		return switch (expression.expr) {
			case TReturn(_):
				true;
			case TThrow(_):
				allowThrow;
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
				definitelyTransfers(inner, allowThrow);
			case TBlock(expressions): expressions.length > 0 && definitelyTransfers(expressions[expressions.length - 1], allowThrow);
			case TIf(_, thenExpression, elseExpression): elseExpression != null && definitelyTransfers(thenExpression,
					allowThrow) && definitelyTransfers(elseExpression, allowThrow);
			case TSwitch(_, cases, defaultExpression):
				defaultExpression != null
				&& cases.length > 0
				&& Lambda.foreach(cases, entry -> definitelyTransfers(entry.expr, allowThrow))
				&& definitelyTransfers(defaultExpression, allowThrow);
			case TTry(tryExpression, catches): definitelyTransfers(tryExpression,
					allowThrow) && catches.length > 0 && Lambda.foreach(catches, entry -> definitelyTransfers(entry.expr, allowThrow));
			case _:
				false;
		}
	}
}
#end
