/**
	A type path in compiler-generated syntax that always starts at the top-level package, whatever
	names the surrounding code declares.

	Why
	- Some compiler rewrites produce ordinary Haxe syntax that names a standard type, for example
	  the macro reification lowering writes `haxe.macro.Expr.ExprDef.EConst(...)` and
	  `Std.string(n)`. Written as a plain identifier chain, the first segment is looked up like any
	  identifier: a local variable, parameter, or field named `haxe` or `Std`, an import alias, or
	  a same-package type named `Std` would be found first. `{ var haxe = 42; macro 1; }` then
	  failed to type, although upstream Haxe builds the quoted tree inside the compiler and never
	  looks at the user's names.
	- Upstream's `std.` prefix (`std.Std.string(1)`) is not enough: a local named `std` captures it.

	What
	- `expression("haxe.macro.Expr.ExprDef")` returns the usual `EIdent` + `EField` chain whose
	  first identifier carries the prefix `::` (`::haxe`, then `.macro`, ...), similar to C++'s
	  global-namespace `::`. The lexer never produces an identifier with `:`, and the macro result
	  importer (`MacroSyntaxImport`) refuses one, so neither source nor a macro result can write,
	  declare, or shadow it.
	- The typer treats a dotted path that starts with `::` as rooted: no local, field, import, or
	  package-relative lookup applies, and `TyperContext.resolveType` resolves the rest from the
	  top-level package. A rooted type that does not resolve is a compile error at the
	  quotation (`TyperStage.requireRootedOwners`). A module typed without a module loader has no
	  classpath to resolve against; the lowering writes plain chains there. Typed output carries the ordinary spelling, and
	  backend projection rejects a rooted name (`assertResolved`), so backends never see the prefix.
**/
class HxRootedPath {
	/** The spelling that marks the first identifier of a rooted path. */
	public static inline final PREFIX = "::";

	/**
		Syntax for the dot-separated `path` (`haxe.macro.Expr.ExprDef`, `Std`), rooted unless `rooted`
		is false (then the ordinary identifier chain, for typing without a classpath).
	**/
	public static function expression(path:String, rooted:Bool = true):HxExpr {
		final parts = path.split(".");
		var out:HxExpr = EIdent((rooted ? PREFIX : "") + parts[0]);
		for (index in 1...parts.length)
			out = EField(out, parts[index]);
		return out;
	}

	/** Whether a dotted path (or identifier) was written by `expression`. */
	public static function isRooted(path:Null<String>):Bool
		return path != null && StringTools.startsWith(path, PREFIX);

	/**
		Fail when a rooted name reaches backend projection.

		The typer resolves every rooted path to its declaration and reports a missing one at the
		quotation, so a rooted spelling here is a compiler bug; a backend would otherwise print the
		prefix (`__hxhxmacrohost` in JavaScript, an invalid OCaml path).
	**/
	public static function assertResolved(name:String):String {
		if (isRooted(name))
			throw "rooted path `" + name + "` reached backend projection without a resolved declaration";
		return name;
	}

	/** The path without its prefix (`::Std.string` gives `Std.string`); other paths are unchanged. */
	public static function unrooted(path:String):String
		return isRooted(path) ? path.substr(PREFIX.length) : path;
}
