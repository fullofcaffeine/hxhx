package hxhx.macro;

typedef MacroPositionInfo = {
	final file:String;
	final min:Int;
	final max:Int;
}

typedef MacroCompilerConfigurationSnapshot = {
	final version:Int;
	final args:Array<String>;
	final debug:Bool;
	final verbose:Bool;
	final foptimize:Bool;
	final stdPath:Array<String>;
	final targetName:String;
	final supportsUnicode:Bool;
}

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
	static inline final DEFAULT_COMPILER_VERSION:Int = 40307;
	static final defines:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	static final ocamlModules:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	static final classPaths:Array<String> = [];
	static final includedModules:Array<String> = [];
	static final compilerArgs:Array<String> = [];
	static final stdPaths:Array<String> = [];
	static var generatedHxDir:String = "";
	static final generatedHxModules:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	static final buildFieldsByModule:haxe.ds.StringMap<Array<String>> = new haxe.ds.StringMap();
	static var buildFieldsPayload:String = "";
	static final afterTypingHookIds:Array<Int> = [];
	static final onGenerateHookIds:Array<Int> = [];
	static final afterGenerateHookIds:Array<Int> = [];
	static var compilerVersion:Int = DEFAULT_COMPILER_VERSION;
	static var debugEnabled:Bool = false;
	static var verboseEnabled:Bool = false;
	static var optimizeEnabled:Bool = true;
	static var compilerTargetName:String = "ocaml";
	static var supportsUnicode:Bool = true;
	static var explicitCurrentPos:Null<MacroPositionInfo> = null;

	static function sortStringsInPlace(arr:Array<String>):Void {
		// Avoid `Array.sort(fn)` during bring-up.
		//
		// Why
		// - `hxhx` itself is compiled by our OCaml backend, and higher-order Array operations
		//   (callbacks/closures) are an unnecessary source of runtime instability while we
		//   are still validating core semantics.
		//
		// What
		// - Insertion-sort in-place using plain loops and string comparisons.
		if (arr == null || arr.length <= 1)
			return;
		var i = 1;
		while (i < arr.length) {
			final key = arr[i];
			var j = i - 1;
			while (j >= 0) {
				final cur = arr[j];
				// Null-safety: treat nulls as empty strings so ordering is deterministic.
				final a = cur == null ? "" : cur;
				final b = key == null ? "" : key;
				if (!(a > b))
					break;
				arr[j + 1] = cur;
				j -= 1;
			}
			arr[j + 1] = key;
			i += 1;
		}
	}

	static function hasArg(args:Array<String>, flag:String):Bool {
		if (args == null || flag == null || flag.length == 0)
			return false;
		for (arg in args)
			if (arg == flag)
				return true;
		return false;
	}

	static function parseCompilerVersionFromDefines():Int {
		final raw = definedValue("haxe_ver");
		if (raw.length == 0)
			return DEFAULT_COMPILER_VERSION;
		final parts = raw.split(".");
		if (parts.length == 0)
			return DEFAULT_COMPILER_VERSION;
		final major = Std.parseInt(parts[0]);
		final minor = parts.length > 1 ? Std.parseInt(parts[1]) : 0;
		final patch = parts.length > 2 ? Std.parseInt(parts[2]) : 0;
		if (major == null || minor == null || patch == null)
			return DEFAULT_COMPILER_VERSION;
		return (major * 10000) + (minor * 100) + patch;
	}

	static function copyUniqueTrimmedStrings(out:Array<String>, values:Array<String>):Void {
		out.resize(0);
		if (values == null || values.length == 0)
			return;
		for (value in values) {
			if (value == null)
				continue;
			final trimmed = StringTools.trim(value);
			if (trimmed.length == 0)
				continue;
			if (out.indexOf(trimmed) == -1)
				out.push(trimmed);
		}
	}

	public static function reset():Void {
		defines.clear();
		ocamlModules.clear();
		classPaths.resize(0);
		includedModules.resize(0);
		compilerArgs.resize(0);
		stdPaths.resize(0);
		generatedHxDir = "";
		generatedHxModules.clear();
		buildFieldsByModule.clear();
		buildFieldsPayload = "";
		afterTypingHookIds.resize(0);
		onGenerateHookIds.resize(0);
		afterGenerateHookIds.resize(0);
		compilerVersion = DEFAULT_COMPILER_VERSION;
		debugEnabled = false;
		verboseEnabled = false;
		optimizeEnabled = true;
		compilerTargetName = "ocaml";
		supportsUnicode = true;
		explicitCurrentPos = null;
	}

	public static function setDefine(name:String, value:String):Void {
		if (name == null || name.length == 0)
			return;
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
		if (defines == null || defines.length == 0)
			return;
		for (raw in defines) {
			if (raw == null)
				continue;
			final s = StringTools.trim(raw);
			if (s.length == 0)
				continue;
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
		if (name == null || name.length == 0)
			return false;
		return defines.exists(name);
	}

	public static function definedValue(name:String):String {
		if (name == null || name.length == 0)
			return "";
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
		for (k in defines.keys())
			out.push(k);
		sortStringsInPlace(out);
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
		Seed the macro-facing compiler configuration snapshot.

		Why
		- Runtime macro modules compiled into the external macro host can call
		  `Compiler.getConfiguration()` even though they are not running inside upstream eval.
		- We therefore need a compiler-owned snapshot that both external-host and future inproc
		  paths can expose consistently.

		What
		- Stores a conservative configuration snapshot:
		  - raw CLI args
		  - resolved std roots
		  - common flag booleans
		  - pinned compiler version target (`4.3.7`)
		  - coarse target identity

		Gotchas
		- This is intentionally smaller than upstream's full internal configuration object.
		  Typed backend/display internals remain outside this bring-up slice.
	**/
	public static function seedCompilerConfiguration(args:Array<String>, stdPathRoots:Array<String>, targetName:String):Void {
		copyUniqueTrimmedStrings(compilerArgs, args);
		copyUniqueTrimmedStrings(stdPaths, stdPathRoots);
		compilerVersion = parseCompilerVersionFromDefines();
		debugEnabled = hasArg(compilerArgs, "--debug") || defined("debug");
		verboseEnabled = hasArg(compilerArgs, "-v") || hasArg(compilerArgs, "--verbose") || defined("verbose");
		optimizeEnabled = !hasArg(compilerArgs, "--no-opt");
		final trimmedTarget = targetName == null ? "" : StringTools.trim(targetName);
		compilerTargetName = trimmedTarget.length == 0 ? "ocaml" : trimmedTarget;
		supportsUnicode = true;
	}

	public static function getCompilerConfigurationSnapshot():MacroCompilerConfigurationSnapshot {
		return {
			version: compilerVersion,
			args: compilerArgs.copy(),
			debug: debugEnabled,
			verbose: verboseEnabled,
			foptimize: optimizeEnabled,
			stdPath: stdPaths.copy(),
			targetName: compilerTargetName,
			supportsUnicode: supportsUnicode
		};
	}

	/**
		Override the current macro position for the active compiler process.

		Why
		- External-host runtime macros need a stable `Context.currentPos()` result for diagnostics
		  and position helper APIs.
		- Tests also need a deterministic way to seed this position without running a full Stage3
		  build-macro pipeline.
	**/
	public static function setCurrentPos(pos:MacroPositionInfo):Void {
		if (pos == null) {
			explicitCurrentPos = null;
			return;
		}
		explicitCurrentPos = {
			file: pos.file == null || pos.file.length == 0 ? "<macro>" : pos.file,
			min: pos.min < 0 ? 0 : pos.min,
			max: pos.max < 0 ? 0 : pos.max
		};
	}

	public static function clearCurrentPos():Void {
		explicitCurrentPos = null;
	}

	public static function getCurrentPos():MacroPositionInfo {
		if (explicitCurrentPos != null)
			return explicitCurrentPos;
		final buildFile = definedValue("HXHX_BUILD_FILE");
		if (buildFile.length > 0) {
			return {file: buildFile, min: 0, max: 0};
		}
		final buildModule = definedValue("HXHX_BUILD_MODULE");
		if (buildModule.length > 0) {
			return {
				file: StringTools.replace(buildModule, ".", "/") + ".hx",
				min: 0,
				max: 0
			};
		}
		return {file: "<macro>", min: 0, max: 0};
	}

	/**
		Hook registration (Stage 4 bring-up).

		Why
		- When macros register callbacks in the macro host, the compiler must remember those
		  hook IDs so it can invoke them at the right time during the compilation pipeline.

		What
		- Stores hook IDs in registration order.
		- Two hook kinds exist in the current bring-up rung:
		  - `afterTyping`
		  - `onGenerate`
		  - `afterGenerate`
	**/
	public static function registerHook(kind:String, id:Int):Void {
		if (kind == null)
			return;
		switch (kind) {
			case "afterTyping":
				afterTypingHookIds.push(id);
			case "onGenerate":
				onGenerateHookIds.push(id);
			case "afterGenerate":
				afterGenerateHookIds.push(id);
			case _:
				// Ignore unknown hook kinds during bring-up.
		}
	}

	public static function listAfterTypingHookIds():Array<Int> {
		return afterTypingHookIds.copy();
	}

	public static function listOnGenerateHookIds():Array<Int> {
		return onGenerateHookIds.copy();
	}

	public static function listAfterGenerateHookIds():Array<Int> {
		return afterGenerateHookIds.copy();
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
		if (name == null)
			return;
		final n = StringTools.trim(name);
		if (n.length == 0)
			return;

		// Conservative OCaml module name check: [A-Za-z_][A-Za-z0-9_]* (no dots, no path separators).
		// We don't enforce initial capital here; `EmitterStage` writes `<name>.ml` and OCaml will treat
		// the unit name as `StringTools.capitalize(name)`. We only care about filesystem safety now.
		inline function isAlpha(c:Int):Bool
			return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code);
		inline function isDigit(c:Int):Bool
			return c >= "0".code && c <= "9".code;
		inline function isUnderscore(c:Int):Bool
			return c == "_".code;
		final first = n.charCodeAt(0);
		if (!(isAlpha(first) || isUnderscore(first)))
			return;
		for (i in 1...n.length) {
			final c = n.charCodeAt(i);
			if (!(isAlpha(c) || isDigit(c) || isUnderscore(c)))
				return;
		}

		ocamlModules.set(n, source == null ? "" : source);
	}

	public static function listOcamlModuleNames():Array<String> {
		final out = new Array<String>();
		for (k in ocamlModules.keys())
			out.push(k);
		sortStringsInPlace(out);
		return out;
	}

	public static function getOcamlModuleSource(name:String):String {
		if (name == null || name.length == 0)
			return "";
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
		if (path == null)
			return;
		final p = StringTools.trim(path);
		if (p.length == 0)
			return;
		if (classPaths.indexOf(p) == -1)
			classPaths.push(p);
	}

	public static function listClassPaths():Array<String> {
		return classPaths.copy();
	}

	/**
		Macro-time “include” roots (bring-up rung).

		Why
		- Upstream `--macro include("pack.Mod")` is used to force modules/types into the compilation
		  even when nothing imports them directly (important for DCE and some unit fixtures).
		- Our Stage3 resolver currently computes the module graph from explicit import closure only.
		  Without an include mechanism, those upstream-style macros have no observable effect.

		What
		- `includeModule(path)` registers `path` as an additional resolver root for the current
		  compilation.
		- Stage3 then treats these included modules as extra roots when building the module graph.

		Gotchas
		- This is not full upstream semantics (it does not model typed reachability or DCE).
		  It is a small rung to validate the “macro changes compilation universe” loop.
	**/
	public static function includeModule(path:String):Void {
		if (path == null)
			return;
		final p = StringTools.trim(path);
		if (p.length == 0)
			return;
		if (includedModules.indexOf(p) == -1)
			includedModules.push(p);
	}

	public static function listIncludedModules():Array<String> {
		return includedModules.copy();
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
		if (name == null)
			return;
		final n = StringTools.trim(name);
		if (n.length == 0)
			return;
		if (generatedHxDir == null || generatedHxDir.length == 0) {
			throw "MacroState.emitHxModule: missing generated hx dir (call setGeneratedHxDir before running macros)";
		}

		// Conservative file-safe module name: [A-Za-z_][A-Za-z0-9_]*
		inline function isAlpha(c:Int):Bool
			return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code);
		inline function isDigit(c:Int):Bool
			return c >= "0".code && c <= "9".code;
		inline function isUnderscore(c:Int):Bool
			return c == "_".code;
		final first = n.charCodeAt(0);
		if (!(isAlpha(first) || isUnderscore(first)))
			return;
		for (i in 1...n.length) {
			final c = n.charCodeAt(i);
			if (!(isAlpha(c) || isDigit(c) || isUnderscore(c)))
				return;
		}

		if (!sys.FileSystem.exists(generatedHxDir))
			sys.FileSystem.createDirectory(generatedHxDir);
		final path = haxe.io.Path.join([generatedHxDir, n + ".hx"]);
		sys.io.File.saveContent(path, source == null ? "" : source);
		generatedHxModules.set(n, source == null ? "" : source);
	}

	public static function hasGeneratedHxModules():Bool {
		for (_ in generatedHxModules.keys())
			return true;
		return false;
	}

	/**
		Stage4 bring-up: allow macros to "emit build fields" as raw Haxe member source strings.

		Why
		- Real Haxe build macros return `Array<haxe.macro.Expr.Field>` and require a full macro
		  interpreter + typed AST integration.
		- Stage 4 bring-up needs an earlier, smaller rung that still validates the pipeline shape:
		  `@:build(...)` metadata triggers a macro-host call and results in *new members* being
		  typed and emitted.
		- Returning structured `Field` values over RPC is future work; today we transport raw Haxe
		  member snippets (that our bootstrap parser can re-parse).

		What
		- `emitBuildFields(modulePath, membersSource)` stores a snippet associated with a module.
		- `listBuildFields(modulePath)` returns snippets in emission order.

		How
		- The macro host calls a reverse RPC `compiler.emitBuildFields m=<modulePath> s=<source>`.
		- The Stage3 pipeline reads the collected snippets and merges the parsed members into the
		  module's main class before typing.
	**/
	public static function emitBuildFields(modulePath:String, membersSource:String):Void {
		if (modulePath == null)
			return;
		final m = StringTools.trim(modulePath);
		if (m.length == 0)
			return;
		final src = membersSource == null ? "" : membersSource;
		var arr = buildFieldsByModule.get(m);
		if (arr == null) {
			arr = [];
			buildFieldsByModule.set(m, arr);
		}
		arr.push(src);
	}

	public static function listBuildFields(modulePath:String):Array<String> {
		if (modulePath == null)
			return [];
		final m = StringTools.trim(modulePath);
		if (m.length == 0)
			return [];
		final arr = buildFieldsByModule.get(m);
		return arr == null ? [] : arr.copy();
	}

	public static function clearBuildFields(modulePath:String):Void {
		if (modulePath == null)
			return;
		final m = StringTools.trim(modulePath);
		if (m.length == 0)
			return;
		buildFieldsByModule.remove(m);
	}

	/**
		Stage4 bring-up: provide a minimal `Context.getBuildFields()` payload to the macro host.

		Why
		- Upstream build macros often start with `Context.getBuildFields()` and then either:
		  - return the same fields (possibly modified), or
		  - push new fields and return the extended list.
		- Our earliest Stage4 `@:build(...)` rung transported *only new members* as raw Haxe snippets via
		  `compiler.emitBuildFields`, which is enough for "add a field" demos but breaks many upstream
		  macros that expect `getBuildFields` to exist.

		What
		- This stores a JSON payload describing the fields of the class currently being built.
		- The macro host retrieves it via reverse RPC `context.getBuildFields`.

		How
		- Stored as a length-prefixed fragment list (so the macro host can parse it with `Protocol.kvParse`):
		  - `c=<count>`
		  - then `n<i>`/`k<i>`/`s<i>`/`v<i>` fragments for each field.

		Gotchas
		- This payload does **not** include full expression bodies or types yet.
		  Stage4 currently uses it to support macros that return *new* fields (delta emission).
	**/
	public static function setBuildFieldsPayload(payload:String):Void {
		buildFieldsPayload = payload == null ? "" : payload;
	}

	public static function getBuildFieldsPayload():String {
		return buildFieldsPayload == null ? "" : buildFieldsPayload;
	}
}
