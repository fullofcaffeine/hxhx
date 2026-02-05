/**
	Module-level AST node for the Haxe-in-Haxe compiler bring-up.

	Why:
	- A full Haxe AST is large; for bootstrapping we start with the minimum
	  information needed to drive acceptance tests and pipeline wiring.
	- This is a nominal class (not an anonymous structure) so the OCaml target can
	  compile it without requiring structural-typing support.

	What:
	- Optional package path (as dotted string, e.g. "a.b.c").
	- Import list (dotted strings).
	- One top-level class declaration (for now).
**/
class HxModuleDecl {
	public final packagePath:String;
	public final imports:Array<String>;
	public final mainClass:HxClassDecl;
	public final headerOnly:Bool;
	public final hasToplevelMain:Bool;

	public function new(packagePath:String, imports:Array<String>, mainClass:HxClassDecl, headerOnly:Bool, hasToplevelMain:Bool) {
		this.packagePath = packagePath;
		this.imports = imports;
		this.mainClass = mainClass;
		this.headerOnly = headerOnly;
		this.hasToplevelMain = hasToplevelMain;
	}

	/**
		Non-inline getter for `packagePath`.

		Why:
		- The generated OCaml is built under dune’s `-opaque` in Dev mode, which
		  can hide record labels across compilation units.
		- Using non-inline getters avoids cross-module record-field access.
	**/
	public static function getPackagePath(m:HxModuleDecl):String {
		return m.packagePath;
	}

	/**
		Non-inline getter for `imports` (see `getPackagePath` rationale).
	**/
	public static function getImports(m:HxModuleDecl):Array<String> {
		return m.imports;
	}

	/**
		Non-inline getter for `mainClass` (see `getPackagePath` rationale).
	**/
	public static function getMainClass(m:HxModuleDecl):HxClassDecl {
		return m.mainClass;
	}

	/**
		Whether this module was produced via native frontend header-only fallback.

		Why
		- During bootstrap, the native OCaml frontend may fall back to parsing only
		  package/import/class headers (when class bodies contain unsupported syntax).
		- Tracking this explicitly lets Gate1 diagnostics avoid “silent success” and
		  quantify progress as we implement more of the real parser.
	**/
	public static function getHeaderOnly(m:HxModuleDecl):Bool {
		return m.headerOnly;
	}

	/**
		Whether the module provides a toplevel `function main(...)` entrypoint.

		Why
		- Upstream Haxe supports module-level entrypoints (used by its unit tests).
		- Supporting this early prevents bootstrap churn when we start running upstream suites.
	**/
	public static function getHasToplevelMain(m:HxModuleDecl):Bool {
		return m.hasToplevelMain;
	}
}
