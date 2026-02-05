package hxhx.macro;

/**
	Compiler-side macro state (Stage 4 bring-up).

	Why
	- The Stage 4 Model A macro host can call back into the compiler while the compiler is waiting
	  for a response (duplex RPC).
	- The first meaningful “macro effect” we support is `Compiler.define(name, value)`.
	- To be useful beyond a single RPC session, defines must live in a compiler-owned store that the
	  rest of the compilation pipeline can query *after* macros have run.

	What
	- A tiny, deterministic define store for bring-up:
	  - `setDefine(name, value)`
	  - `defined(name)` / `definedValue(name)`
	  - `reset()` between compilations/tests

	How
	- Implemented as a `StringMap<String>` so it compiles cleanly to OCaml without relying on target
	  runtime shims.
	- This is intentionally minimal and will eventually be replaced by the real compiler context that
	  also tracks classpaths, metadata, generated fields, etc.

	Gotchas
	- This is global state. Always call `reset()` at the start of any compilation entrypoint that may
	  execute macros (Stage 3 bring-up, Stage 4 selftests, upstream gate runners).
**/
class MacroState {
	static final defines:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	static final ocamlModules:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	static final classPaths:Array<String> = [];
	static var generatedHxDir:String = "";
	static final generatedHxModules:haxe.ds.StringMap<String> = new haxe.ds.StringMap();

	public static function reset():Void {
		defines.clear();
		ocamlModules.clear();
		classPaths.resize(0);
		generatedHxDir = "";
		generatedHxModules.clear();
	}

	public static function setDefine(name:String, value:String):Void {
		if (name == null || name.length == 0) return;
		defines.set(name, value == null ? "" : value);
	}

	/**
		Seed defines from `-D` arguments.

		Why
		- Real compilations have an initial define set (CLI `-D`, target defaults, etc.).
		- Macros expect `Context.defined*` to reflect those defines.

		What
		- Accepts a list of raw `-D` strings in either form:
		  - `NAME`
		  - `NAME=VALUE`
		- Stores them as:
		  - `NAME → "1"` for the bare form
		  - `NAME → VALUE` for the `=` form
	**/
	public static function seedFromCliDefines(defines:Array<String>):Void {
		if (defines == null || defines.length == 0) return;
		for (raw in defines) {
			if (raw == null) continue;
			final s = StringTools.trim(raw);
			if (s.length == 0) continue;
			final eq = s.indexOf("=");
			if (eq == -1) {
				setDefine(s, "1");
			} else if (eq == 0) {
				// Ignore invalid `=VALUE` forms.
			} else {
				setDefine(s.substr(0, eq), s.substr(eq + 1));
			}
		}
	}

	public static function defined(name:String):Bool {
		if (name == null || name.length == 0) return false;
		return defines.exists(name);
	}

	public static function definedValue(name:String):String {
		if (name == null || name.length == 0) return "";
		final v = defines.get(name);
		return v == null ? "" : v;
	}

	/**
		Return define names in a stable order.

		Why
		- Useful for bring-up tests and diagnostics: we want deterministic output.

		What
		- Returns a sorted array of define keys.
	**/
	public static function listDefineNames():Array<String> {
		final out = new Array<String>();
		for (k in defines.keys()) out.push(k);
		out.sort((a, b) -> (a < b ? -1 : (a > b ? 1 : 0)));
		return out;
	}

	/**
		Return a JSON-serializable snapshot of all defines.

		Why
		- Stage4 reverse RPC is string-based, so complex payloads need a stable encoding.
		- Using a list of `[key, value]` pairs preserves ordering and avoids relying on map serialization.

		What
		- Returns an array of `[key, value]` pairs sorted by key.
	**/
	public static function listDefinesPairsSorted():Array<Array<String>> {
		final out = new Array<Array<String>>();
		for (k in listDefineNames()) {
			out.push([k, definedValue(k)]);
		}
		return out;
	}

	/**
		Register an OCaml module to be emitted by the compilation pipeline.

		Why
		- This is our first concrete “generate code” effect for Stage 4:
		  a macro can ask the compiler to emit additional target files.

		What
		- Stores an OCaml module as:
		  - `name` (OCaml compilation unit name, e.g. `HxHxGen`)
		  - `source` (raw `.ml` contents)

		How
		- Validates `name` with a conservative allowlist so generated filenames are safe and deterministic.
	**/
	public static function emitOcamlModule(name:String, source:String):Void {
		if (name == null) return;
		final n = StringTools.trim(name);
		if (n.length == 0) return;

		// Conservative OCaml module name check: [A-Za-z_][A-Za-z0-9_]* (no dots, no path separators).
		// We don't enforce initial capital here; `EmitterStage` writes `<name>.ml` and OCaml will treat
		// the unit name as `StringTools.capitalize(name)`. We only care about filesystem safety now.
		inline function isAlpha(c:Int):Bool return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code);
		inline function isDigit(c:Int):Bool return c >= "0".code && c <= "9".code;
		inline function isUnderscore(c:Int):Bool return c == "_".code;
		final first = n.charCodeAt(0);
		if (!(isAlpha(first) || isUnderscore(first))) return;
		for (i in 1...n.length) {
			final c = n.charCodeAt(i);
			if (!(isAlpha(c) || isDigit(c) || isUnderscore(c))) return;
		}

		ocamlModules.set(n, source == null ? "" : source);
	}

	public static function listOcamlModuleNames():Array<String> {
		final out = new Array<String>();
		for (k in ocamlModules.keys()) out.push(k);
		out.sort((a, b) -> (a < b ? -1 : (a > b ? 1 : 0)));
		return out;
	}

	public static function getOcamlModuleSource(name:String):String {
		if (name == null || name.length == 0) return "";
		final v = ocamlModules.get(name);
		return v == null ? "" : v;
	}

	/**
		Macro-time classpaths added via `Compiler.addClassPath`.

		Why
		- This is an early “macro influences compilation” effect that does not require typed AST transforms:
		  it changes which modules can be resolved.
	**/
	public static function addClassPath(path:String):Void {
		if (path == null) return;
		final p = StringTools.trim(path);
		if (p.length == 0) return;
		if (classPaths.indexOf(p) == -1) classPaths.push(p);
	}

	public static function listClassPaths():Array<String> {
		return classPaths.copy();
	}

	/**
		Set the directory where `emitHxModule` writes `.hx` files for this compilation.

		Why
		- The macro host should not need to know our output layout.
		- Stage3 (compiler entrypoint) decides where generated code should live.
	**/
	public static function setGeneratedHxDir(dir:String):Void {
		generatedHxDir = dir == null ? "" : StringTools.trim(dir);
	}

	public static function getGeneratedHxDir():String {
		return generatedHxDir;
	}

	/**
		Emit a Haxe module into the generated hx directory.

		Why
		- This is a bring-up rung for “macro generates code that affects compilation”, without
		  implementing typed AST transforms yet.

		What
		- Writes `<generatedHxDir>/<Name>.hx` with the provided source.
		- Records the module so tests can assert what was emitted.
	**/
	public static function emitHxModule(name:String, source:String):Void {
		if (name == null) return;
		final n = StringTools.trim(name);
		if (n.length == 0) return;
		if (generatedHxDir == null || generatedHxDir.length == 0) {
			throw "MacroState.emitHxModule: missing generated hx dir (call setGeneratedHxDir before running macros)";
		}

		// Conservative file-safe module name: [A-Za-z_][A-Za-z0-9_]*
		inline function isAlpha(c:Int):Bool return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code);
		inline function isDigit(c:Int):Bool return c >= "0".code && c <= "9".code;
		inline function isUnderscore(c:Int):Bool return c == "_".code;
		final first = n.charCodeAt(0);
		if (!(isAlpha(first) || isUnderscore(first))) return;
		for (i in 1...n.length) {
			final c = n.charCodeAt(i);
			if (!(isAlpha(c) || isDigit(c) || isUnderscore(c))) return;
		}

		if (!sys.FileSystem.exists(generatedHxDir)) sys.FileSystem.createDirectory(generatedHxDir);
		final path = haxe.io.Path.join([generatedHxDir, n + ".hx"]);
		sys.io.File.saveContent(path, source == null ? "" : source);
		generatedHxModules.set(n, source == null ? "" : source);
	}

	public static function hasGeneratedHxModules():Bool {
		for (_ in generatedHxModules.keys()) return true;
		return false;
	}
}
