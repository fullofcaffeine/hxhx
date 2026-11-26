/**
	A macro that parses text holding conditional compilation, as upstream's test builder parses
	each `.unit.hx` file with `Context.parseInlineString` (haxe_ocaml-w1zmu). Upstream's lexer
	evaluates `#if`, `#elseif`, `#else`, and `#end` with the compilation's defines, the ones
	`Context.defined` reports (`src/typing/macroContext.ml`: `ctx.com.defines`).
**/
class Parsed {
	public static macro function pick(code:String):haxe.macro.Expr {
		#if macro
		return haxe.macro.Context.parseInlineString(code, haxe.macro.Context.currentPos());
		#else
		return null;
		#end
	}
}
