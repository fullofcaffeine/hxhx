/**
	Module-level AST node for the Haxe-in-Haxe compiler bring-up.

	Why:
	- A full Haxe AST is large; for bootstrapping we start with the minimum
	  information needed to drive acceptance tests and pipeline wiring.
	- This is a nominal class (not an anonymous structure) so the OCaml target can
	  compile it without requiring structural-typing support.

	What:
	- Optional package path (as dotted string, e.g. "a.b.c").
	- Ordered import/using directives with their source-language meaning intact.
	- One or more top-level class declarations.

	Note
	- Haxe modules may contain multiple types. For bootstrap we only model `class`
	  declarations, but we keep *all* of them so Stage3 emission can resolve
	  module-local helper types (common in upstream unit tests).
**/
class HxModuleDecl {
	public final packagePath:String;

	final directives:Array<HxModuleDirective>;

	public final mainClass:HxClassDecl;
	public final classes:Array<HxClassDecl>;
	public final headerOnly:Bool;
	public final hasToplevelMain:Bool;

	public function new(packagePath:String, directives:Array<HxModuleDirective>, mainClass:HxClassDecl, classes:Array<HxClassDecl>, headerOnly:Bool,
			hasToplevelMain:Bool) {
		this.packagePath = packagePath;
		this.directives = directives == null ? [] : directives.copy();
		this.mainClass = mainClass;
		// Keep `classes` non-empty and consistent with `mainClass` for downstream stages.
		if (classes == null || classes.length == 0) {
			this.classes = [mainClass];
		} else {
			var hasMain = false;
			for (c in classes) {
				if (c == mainClass) {
					hasMain = true;
					break;
				}
			}
			this.classes = hasMain ? classes : ([mainClass].concat(classes));
		}
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
		Non-inline getter for module directives (see `getPackagePath` rationale).
	**/
	public static function getDirectives(m:HxModuleDecl):Array<HxModuleDirective> {
		return m.directives.copy();
	}

	/**
		Non-inline getter for `mainClass` (see `getPackagePath` rationale).
	**/
	public static function getMainClass(m:HxModuleDecl):HxClassDecl {
		return m.mainClass;
	}

	/**
		Non-inline getter for `classes` (see `getPackagePath` rationale).

		Why
		- Stage3 emission needs to know about *all* module-local class declarations
		  so it can emit compilation units for helper types (e.g. `private class Foo`)
		  referenced by the main class.
	**/
	public static function getClasses(m:HxModuleDecl):Array<HxClassDecl> {
		return m.classes;
	}

	/**
		Whether this module contains only declaration-header facts.

		Why
		- Best-effort parsing may preserve enough package/import/class information for
		  diagnostics even when complete declaration bodies are unavailable.
		- Tracking that incompleteness explicitly prevents downstream stages from
		  treating a partial module as fully parsed.
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
