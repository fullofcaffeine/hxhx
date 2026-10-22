import hxhx.ExprMacroExpander;
import hxhx.macro.MacroRuntimeSession;

/** Check source traversal independently of native macro argument transport. */
@:access(hxhx.ExprMacroExpander)
class M14ExpressionMacroSourceTraversalTest {
	static function main():Void {
		final calls = new Array<String>();
		final session:MacroRuntimeSession = {
			run: _ -> throw "unexpected macro run",
			runHook: (_, _) -> throw "unexpected macro hook",
			runTypeNotFoundHook: (_, _) -> throw "unexpected type hook",
			expandExpr: expression -> {
				calls.push(expression);
				return switch expression {
					case "First.expand()": '"first"';
					case "Second.expand()": '"second"';
					case _: throw "unexpected expansion";
				};
			},
			close: () -> {}
		};
		final allowed = new haxe.ds.StringMap<Bool>();
		final keys = ["First.expand()", "Second.expand()"];
		for (key in keys)
			allowed.set(key, true);
		var count = 0;
		function rewrite(source:HxExpr):HxExpr {
			return ExprMacroExpander.rewriteExpr(source, session, allowed, keys, new haxe.ds.StringMap<String>(), "", false, 0, () -> count++);
		}
		final position = new HxPos(7, 2, 3);
		final catchFacts = new HxSourceCatch("error", "Dynamic", position);
		final source = HxExpr.ESourceTry([catchFacts], [
			EParenthesized(ECall(EField(EIdent("First"), "expand"), []), position),
			EParenthesized(ECall(EField(EIdent("Second"), "expand"), []), position)
		], position);
		final rewritten = rewrite(source);
		switch rewritten {
			case ESourceTry(catches, [
				EParenthesized(EString("first"), first),
				EParenthesized(EString("second"), second)
			], enclosing):
				if (catches.length != 1 || catches[0] != catchFacts || first != position || second != position || enclosing != position)
					throw "source traversal changed catch facts or positions";
			case _:
				throw "source traversal lost parentheses, handler order, or expansions";
		}
		if (calls.join(";") != keys.join(";") || count != 2)
			throw "source traversal did not expand each child exactly once";
		if (rewrite(rewritten) != rewritten || count != 2)
			throw "unchanged source syntax lost its identity";
		switch source {
			case ESourceTry(_, [EParenthesized(ECall(_, []), _), EParenthesized(ECall(_, []), _)], _):
			case _:
				throw "source traversal mutated its input";
		}
		if (ExprMacroExpander.exprKind(source) != "SourceTry"
			|| ExprMacroExpander.exprKind(EParenthesized(ENull, position)) != "Parenthesized")
			throw "macro trace lost the authored node kind";
		Sys.println("M14_EXPRESSION_MACRO_SOURCE_TRAVERSAL:PASS");
	}
}
