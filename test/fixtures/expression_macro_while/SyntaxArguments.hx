import haxe.macro.Context;
import haxe.macro.Expr;

/** Check a real syntax argument without evaluating or typing its identifiers. */
class SyntaxArguments {
	public static macro function inspect(value:Expr):Expr {
		switch value.expr {
			case EWhile({expr: EConst(CIdent("unresolvedCondition"))}, {
				expr: EBlock([
					{expr: ECall({expr: EConst(CIdent("unresolvedTick"))}, [{expr: EConst(CIdent("unresolvedCondition"))}])}
				])
			}, true):
			case _:
				throw "Changed loop condition, body, or loop kind";
		}
		final position = Context.getPosInfos(value.pos);
		final source = sys.io.File.getContent(position.file);
		final written = source.substring(position.min, position.max);
		if (written != "while (unresolvedCondition) {\n\t\t\tunresolvedTick(unresolvedCondition);\n\t\t}")
			throw "Changed loop source position";
		return macro "syntax-ok";
	}
}
