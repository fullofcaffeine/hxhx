package hxhxmacros;

/**
	Bring-up helper for expression macro expansion tests.

	Why
	- Stage4 adds a new `macro.expandExpr` RPC, which returns a Haxe expression text snippet
	  to be parsed/spliced by the compiler.
	- To keep the first rung deterministic and non-reflective, we dispatch expression-macro
	  expansions through the macro host’s generated entrypoint registry (exact expression match).

	What
	- `hello()` returns a *Haxe expression snippet* (not a plain string value):
	  - `"HELLO"`

	How
	- `hxhx` will call `macro.expandExpr` with the exact call text:
	  - `hxhxmacros.ExprMacroShim.hello()`
	- The macro host dispatches it via `EntryPointsGen` and returns the snippet.
	- The compiler parses it with `HxParser.parseExprText` and replaces the call site.
**/
class ExprMacroShim {
	public static function hello():String {
		return "\"HELLO\"";
	}
}

