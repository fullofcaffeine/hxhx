package hxhxmacrohost;

#if macro
import haxe.macro.Expr;
#end

/**
	A typed macro shim around `untyped __ocaml__(...)` for macro-host owned code.

	Why
	- The OCaml backend lowers raw `__ocaml__` injections, but some compilation contexts reject
	  direct source callsites in framework code before lowering runs.
	- Sibling targets already solve this by routing raw target-code injection through a typed macro
	  helper. The helper keeps ownership obvious and avoids scattering direct `untyped __ocaml__`
	  calls through macro-host internals.

	What
	- `OcamlInjection.__ocaml__(code, args...)` expands to
	  `untyped __ocaml__(code, ...args)`.
	- Callers can use `{0}`, `{1}`, ... placeholders. The backend keeps each referenced expression
	  as typed target syntax until the final printer runs. This matters when an argument uses a
	  compiler-owned runtime helper: normal runtime authorization still sees that use instead of
	  losing it inside an early-rendered string.
**/
class OcamlInjection {
	public static macro function __ocaml__(code:String, args:Array<Expr>):Expr {
		final pos = haxe.macro.Context.currentPos();
		if (!haxe.macro.Context.defined("ocaml_output")) {
			return {
				expr: EThrow({
					expr: EConst(CString("OcamlInjection.__ocaml__ requires ocaml_output", DoubleQuotes)),
					pos: pos
				}),
				pos: pos
			};
		}
		final callArgs = [
			{
				expr: EConst(CString(code, DoubleQuotes)),
				pos: pos
			}
		].concat(args == null ? [] : args);
		final rawCall:Expr = {
			expr: ECall({
				expr: EConst(CIdent("__ocaml__")),
				pos: pos
			}, callArgs),
			pos: pos
		};
		return {
			expr: EUntyped(rawCall),
			pos: pos
		};
	}
}
