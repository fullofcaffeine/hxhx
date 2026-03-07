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
	- Callers can use `{0}`, `{1}`, ... placeholders; backend lowering is responsible for rendering
	  the referenced expressions into OCaml source.
**/
class OcamlInjection {
	public static macro function __ocaml__(code:String, args:Array<Expr>):Expr {
		final callArgs = [macro $v{code}].concat(args);
		return macro untyped __ocaml__($a{callArgs});
	}
}
