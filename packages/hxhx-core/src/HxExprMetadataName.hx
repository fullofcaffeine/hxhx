/**
	The name of expression metadata as typing and the backends read it.

	Why
	- Ordinary parsing keeps expression metadata as `__hxhx_expr_meta(name, arguments, expr)` with
	  the name as written, colon included (`@:keep` is `":keep"`, `@probe` is `"probe"`), so a macro
	  receives the exact spelling (haxe_ocaml-1d2zn), as upstream's `EMeta` keeps it.
	- Typing and every backend read the name without that colon, as they did when the parser
	  dropped it. `plain` gives that name, so their results stay byte-identical.
**/
class HxExprMetadataName {
	/** `name` without one leading colon. */
	public static function plain(name:String):String
		return name != null && StringTools.startsWith(name, ":") ? name.substr(1) : name;
}
