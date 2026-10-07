/** Obtain upstream parser output directly; Haxe 4.3.7 reification drops generic parameter metadata. */
class SourceGenericFunctionSyntaxOracle {
	public static macro function parsed(source:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr.ExprOf<String> {
		final text = switch source.expr {
			case EConst(CString(value, _)): value;
			case _: haxe.macro.Context.error("syntax oracle requires a literal source string", source.pos);
		};
		final parsed = haxe.macro.Context.parse(text, source.pos);
		return macro $v{haxe.macro.ExprTools.toString(parsed)};
	}
}
