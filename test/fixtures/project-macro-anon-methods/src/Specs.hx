/**
	A macro that parses spec text with structure types that declare methods, as upstream's test
	builder parses `tests/unit/src/unitstd/AnonFieldAccess.unit.hx` (haxe_ocaml-lsk9z). The parsed
	expression comes back to the compiler, which imports its structure types.
**/
class Specs {
	public static macro function check(code:String):haxe.macro.Expr {
		#if macro
		return haxe.macro.Context.parseInlineString(code, haxe.macro.Context.currentPos());
		#else
		return null;
		#end
	}
}
