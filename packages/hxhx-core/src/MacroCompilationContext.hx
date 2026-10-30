import haxe.io.Path;

/**
	Decides which modules of one compilation request are compiled as macro code.

	Why
	- Upstream Haxe types macro code in a separate *macro context*: a compilation in which `macro`
	  and `eval` are defined, so `#if macro` and `#if eval` branches are active. Code typed for the
	  program being compiled (the *target context*) does not see those defines.
	- hxhx runs a project's expression macros from a native plugin that its own OCaml emitter
	  builds. That plugin compilation must see the macro classes the way upstream's macro context
	  sees them, while the standard library it links against keeps its ordinary OCaml-target
	  branches (the eval-only branches of the standard library have no OCaml implementation).
	- Before this owner existed, the resolver and the lazy loader each carried a copy of one fixed
	  rule (`haxe.macro.*` modules get `macro` and `eval`). The rule now lives here, and a request
	  can widen it to its own macro classpaths.

	What
	- A module is a macro module when its module path starts with `haxe.macro.` or its source file
	  lies under `haxe/macro/` (the existing standard-library rule), or when the classpath that
	  contains its source file is one of the request's macro classpaths.
	- When classpaths are nested, the longest containing classpath decides. For example, with the
	  macro classpath `/work` and the ordinary classpath `/work/std`, `/work/std/Map.hx` stays in the
	  target context.
	- `definesFor` returns the request defines unchanged for an ordinary module, and a copy with
	  `macro=1` and `eval=1` added (existing values kept) for a macro module.

	How
	- `standardMacroModulesOnly()` is the context of every ordinary compile.
	- `forMacroClassPaths(macroRoots, allClassPaths)` is the context of a macro compilation, such as
	  a project-macro plugin build (`--hxhx-macro-classpath <dir>`). Both lists hold the absolute
	  classpaths the request resolves modules through.
	- Paths are compared after `Path.normalize`, with `/` and `\` treated alike.

	Gotchas
	- The `ocaml` target define stays defined for macro modules, because the plugin is compiled to
	  OCaml. Upstream's eval macro context does not define the program's target, so `#if ocaml`
	  inside a macro class can differ from upstream (recorded in
	  `docs/00-project/EXPRESSION_MACRO_ARGUMENT_PLAN.md`).
**/
class MacroCompilationContext {
	final roots:Array<MacroClassPathRoot>;

	function new(roots:Array<MacroClassPathRoot>) {
		this.roots = roots;
	}

	/** The context of an ordinary compile: only `haxe.macro.*` modules are macro modules. */
	public static function standardMacroModulesOnly():MacroCompilationContext {
		return new MacroCompilationContext([]);
	}

	/**
		The context of a macro compilation.

		`macroRoots` are the classpaths whose modules are macro code. `allClassPaths` are every
		classpath the request resolves through; listing them lets a nested ordinary classpath keep
		its own modules out of the macro context. A macro root that is missing from `allClassPaths`
		still counts.
	**/
	public static function forMacroClassPaths(macroRoots:Array<String>, allClassPaths:Array<String>):MacroCompilationContext {
		final macroKeys = [for (root in macroRoots) directoryKey(root)];
		final roots = new Array<MacroClassPathRoot>();
		function add(path:String):Void {
			final key = directoryKey(path);
			for (existing in roots)
				if (existing.key == key)
					return;
			roots.push({key: key, isMacro: macroKeys.indexOf(key) >= 0});
		}
		for (path in macroRoots)
			add(path);
		for (path in allClassPaths)
			add(path);
		return new MacroCompilationContext(roots);
	}

	/** Whether the module in `filePath` (`modulePath` may be empty) is compiled as macro code. */
	public function isMacroModule(modulePath:Null<String>, filePath:Null<String>):Bool {
		if (modulePath != null && StringTools.startsWith(modulePath, "haxe.macro."))
			return true;
		if (filePath == null || filePath.length == 0)
			return false;
		final file = slashes(Path.normalize(filePath));
		if (file.indexOf("/haxe/macro/") != -1)
			return true;
		var best:Null<MacroClassPathRoot> = null;
		for (root in roots)
			if (StringTools.startsWith(file, root.key) && (best == null || root.key.length > best.key.length))
				best = root;
		return best != null && best.isMacro;
	}

	/** The defines the module's source is filtered with before parsing. */
	public function definesFor(modulePath:Null<String>, filePath:Null<String>, base:haxe.ds.StringMap<String>):haxe.ds.StringMap<String> {
		if (!isMacroModule(modulePath, filePath))
			return base;
		final out = new haxe.ds.StringMap<String>();
		if (base != null)
			for (name in base.keys())
				out.set(name, base.get(name));
		if (!out.exists("macro"))
			out.set("macro", "1");
		if (!out.exists("eval"))
			out.set("eval", "1");
		return out;
	}

	static function slashes(path:String):String
		return StringTools.replace(path, "\\", "/");

	/** A normalized directory path with one trailing `/`, so prefix tests match whole segments. */
	static function directoryKey(path:String):String {
		final normalized = slashes(Path.normalize(path == null ? "" : path));
		return StringTools.endsWith(normalized, "/") ? normalized : normalized + "/";
	}
}

private typedef MacroClassPathRoot = {
	final key:String;
	final isMacro:Bool;
}
