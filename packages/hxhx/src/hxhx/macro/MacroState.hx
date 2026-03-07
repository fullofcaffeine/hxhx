package hxhx.macro;

import haxe.io.Bytes;

typedef MacroPositionInfo = {
	final file:String;
	final min:Int;
	final max:Int;
}

typedef MacroMessageSnapshot = {
	final kind:String;
	final msg:String;
	final pos:MacroPositionInfo;
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

typedef MacroLocalContextSnapshot = {
	final modulePath:String;
	@:optional final methodName:Null<String>;
	@:optional final localTypeText:Null<String>;
	@:optional final expectedTypeText:Null<String>;
	@:optional final callArgumentExprTexts:Array<String>;
	@:optional final localTVars:Array<MacroLocalTVarSnapshot>;
}

typedef MacroLocalTVarSnapshot = {
	final name:String;
	final typeText:String;
	@:optional final id:Null<Int>;
	@:optional final capture:Null<Bool>;
	@:optional final isStatic:Null<Bool>;
}

typedef MacroModuleDependencySnapshot = {
	final modulePath:String;
	final externFile:String;
}

typedef MacroGlobalMetadataSnapshot = {
	final pathFilter:String;
	final metadata:String;
	final recursive:Bool;
	final toTypes:Bool;
	final toFields:Bool;
}

typedef MacroCustomMetadataSnapshot = {
	final metadata:String;
	final doc:String;
	@:optional final source:Null<String>;
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
	static final resources:haxe.ds.StringMap<Bytes> = new haxe.ds.StringMap();
	static final moduleDependencies:Array<MacroModuleDependencySnapshot> = [];
	static final globalMetadataRules:Array<MacroGlobalMetadataSnapshot> = [];
	static final customMetadataEntries:Array<MacroCustomMetadataSnapshot> = [];
	static final compilerArgs:Array<String> = [];
	static final stdPaths:Array<String> = [];
	static var generatedHxDir:String = "";
	static final generatedHxModules:haxe.ds.StringMap<String> = new haxe.ds.StringMap();
	static final buildFieldsByModule:haxe.ds.StringMap<Array<String>> = new haxe.ds.StringMap();
	static var buildFieldsPayload:String = "";
	static final afterTypingHookIds:Array<Int> = [];
	static final onGenerateHookIds:Array<Int> = [];
	static final afterGenerateHookIds:Array<Int> = [];
	static final onTypeNotFoundHookIds:Array<Int> = [];
	static final messages:Array<MacroMessageSnapshot> = [];
	static var compilerVersion:Int = DEFAULT_COMPILER_VERSION;
	static var debugEnabled:Bool = false;
	static var verboseEnabled:Bool = false;
	static var optimizeEnabled:Bool = true;
	static var compilerTargetName:String = "ocaml";
	static var supportsUnicode:Bool = true;
	static var explicitCurrentPos:Null<MacroPositionInfo> = null;
	static var explicitLocalContext:Null<MacroLocalContextSnapshot> = null;
	static var explicitMainExprText:Null<String> = null;
	static var nextSyntheticLocalTVarId:Int = 1;

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
		resources.clear();
		moduleDependencies.resize(0);
		globalMetadataRules.resize(0);
		customMetadataEntries.resize(0);
		compilerArgs.resize(0);
		stdPaths.resize(0);
		generatedHxDir = "";
		generatedHxModules.clear();
		buildFieldsByModule.clear();
		buildFieldsPayload = "";
		afterTypingHookIds.resize(0);
		onGenerateHookIds.resize(0);
		afterGenerateHookIds.resize(0);
		onTypeNotFoundHookIds.resize(0);
		messages.resize(0);
		compilerVersion = DEFAULT_COMPILER_VERSION;
		debugEnabled = false;
		verboseEnabled = false;
		optimizeEnabled = true;
		compilerTargetName = "ocaml";
		supportsUnicode = true;
		explicitCurrentPos = null;
		explicitLocalContext = null;
		explicitMainExprText = null;
		nextSyntheticLocalTVarId = 1;
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
		Store a macro resource in the compiler-owned state.

		Why
		- Runtime external-host macros may call `Context.addResource(...)` to publish generated
		  resource payloads for later compiler/runtime consumption.
		- The external host cannot own those resources because they must survive after the RPC call.

		What
		- Stores a copy of `data` by `name`.
		- Later writes replace earlier values, matching upstream overwrite behavior.
	**/
	public static function addResource(name:String, data:Bytes):Void {
		if (name == null || name.length == 0 || data == null)
			return;
		resources.set(name, data.sub(0, data.length));
	}

	public static function getResource(name:String):Null<Bytes> {
		if (name == null || name.length == 0)
			return null;
		final value = resources.get(name);
		return value == null ? null : value.sub(0, value.length);
	}

	public static function listResourceNames():Array<String> {
		final out = new Array<String>();
		for (k in resources.keys())
			out.push(k);
		sortStringsInPlace(out);
		return out;
	}

	public static function listResourcesPairsSorted():Array<{name:String, data:Bytes}> {
		final out = new Array<{name:String, data:Bytes}>();
		for (name in listResourceNames()) {
			final data = resources.get(name);
			if (data != null)
				out.push({name: name, data: data.sub(0, data.length)});
		}
		return out;
	}

	/**
		Register a compiler-owned module dependency snapshot.

		Why
		- Reflaxe-style helper layers may call `Context.registerModuleDependency(...)` to announce
		  that a module depends on an external file.
		- The compiler, not the host process, must retain that information after the RPC call returns.

		What
		- Stores distinct `(modulePath, externFile)` pairs in registration order.

		Gotchas
		- This is a compatibility ledger rung only. It does not yet change code generation, DCE, or
		  module graph semantics by itself.
	**/
	public static function registerModuleDependency(modulePath:String, externFile:String):Void {
		if (modulePath == null || externFile == null)
			return;
		final mp = StringTools.trim(modulePath);
		final ef = StringTools.trim(externFile);
		if (mp.length == 0 || ef.length == 0)
			return;
		for (entry in moduleDependencies)
			if (entry.modulePath == mp && entry.externFile == ef)
				return;
		moduleDependencies.push({modulePath: mp, externFile: ef});
	}

	public static function listModuleDependencies():Array<MacroModuleDependencySnapshot> {
		final out = new Array<MacroModuleDependencySnapshot>();
		for (entry in moduleDependencies)
			out.push({modulePath: entry.modulePath, externFile: entry.externFile});
		return out;
	}

	/**
		Register a compiler-owned global metadata rule snapshot.

		Why
		- Reflaxe-style compiler initialization commonly uses `Compiler.addGlobalMetadata(...)` to
		  attach target annotations and global `@:build(...)` hooks before the rest of compilation runs.
		- The external-host runtime needs a stable compiler-owned record even before full metadata
		  application semantics are wired through the typer.

		What
		- Stores distinct `(pathFilter, metadata, recursive, toTypes, toFields)` rules in registration
		  order.

		Gotchas
		- This is currently a compatibility ledger rung. It does not yet claim full upstream semantic
		  application of metadata to typed modules.
	**/
	public static function registerGlobalMetadata(pathFilter:String, metadata:String, recursive:Bool, toTypes:Bool, toFields:Bool):Void {
		final pf = pathFilter == null ? "" : StringTools.trim(pathFilter);
		final md = metadata == null ? "" : StringTools.trim(metadata);
		if (md.length == 0)
			return;
		for (entry in globalMetadataRules)
			if (entry.pathFilter == pf && entry.metadata == md && entry.recursive == recursive && entry.toTypes == toTypes && entry.toFields == toFields)
				return;
		globalMetadataRules.push({
			pathFilter: pf,
			metadata: md,
			recursive: recursive,
			toTypes: toTypes,
			toFields: toFields
		});
	}

	public static function listGlobalMetadataRules():Array<MacroGlobalMetadataSnapshot> {
		final out = new Array<MacroGlobalMetadataSnapshot>();
		for (entry in globalMetadataRules)
			out.push({
				pathFilter: entry.pathFilter,
				metadata: entry.metadata,
				recursive: entry.recursive,
				toTypes: entry.toTypes,
				toFields: entry.toFields
			});
		return out;
	}

	/**
		Return the registered non-build type-level metadata strings that apply to `modulePath`.

		Why
		- Stage3 already feeds registered global `@:build(...)` / `@:autoBuild(...)` metadata into the
		  build-macro queue.
		- External-host runtime queries such as `Context.getModule()` still need an honest, observable
		  semantic bridge for registered non-build type metadata, even before the compiler stores rich
		  source metadata in the AST.

		What
		- Matches registered global metadata rules against the provided module path using the same
		  path-filter semantics as the build-macro bridge.
		- Returns only:
		  - type-level rules (`toTypes=true`)
		  - non-build metadata payloads (plain metadata like `@:demoMeta`, `@:nullSafety(Strict)`)

		Gotchas
		- This does not claim field-level metadata application.
		- This does not claim full upstream metadata semantics; it is a narrow bridge for runtime
		  metadata visibility on synthetic type/module refs.
	**/
	public static function listAppliedTypeMetadata(modulePath:String):Array<String> {
		final moduleName = modulePath == null ? "" : StringTools.trim(modulePath);
		if (moduleName.length == 0)
			return [];
		final out = new Array<String>();
		for (rule in globalMetadataRules) {
			if (!rule.toTypes)
				continue;
			if (!matchesMetadataPathFilter(moduleName, rule.pathFilter, rule.recursive))
				continue;
			if (isBuildMetadata(rule.metadata))
				continue;
			if (out.indexOf(rule.metadata) == -1)
				out.push(rule.metadata);
		}
		return out;
	}

	static function matchesMetadataPathFilter(modulePath:String, pathFilter:String, recursive:Bool):Bool {
		final moduleName = modulePath == null ? "" : StringTools.trim(modulePath);
		final filter = pathFilter == null ? "" : StringTools.trim(pathFilter);
		if (moduleName.length == 0)
			return false;
		if (filter.length == 0)
			return true;
		if (recursive)
			return moduleName == filter || StringTools.startsWith(moduleName, filter + ".");
		return moduleName == filter;
	}

	static function isBuildMetadata(metadata:String):Bool {
		final raw = metadata == null ? "" : StringTools.trim(metadata);
		return StringTools.startsWith(raw, "@:build(") || StringTools.startsWith(raw, "@:autoBuild(");
	}

	/**
		Register a compiler-owned custom metadata descriptor snapshot.

		Why
		- Reflaxe reflection helpers can register custom metadata descriptions for display/editor
		  consumers.
		- The compiler must retain a stable description ledger even before richer display integration
		  is available.

		What
		- Stores distinct metadata names with their documentation and optional source label.
	**/
	public static function registerCustomMetadata(metadata:String, doc:String, ?source:String):Void {
		final md = metadata == null ? "" : StringTools.trim(metadata);
		if (md.length == 0)
			return;
		for (entry in customMetadataEntries)
			if (entry.metadata == md)
				return;
		customMetadataEntries.push({
			metadata: md,
			doc: doc == null ? "" : doc,
			source: source == null ? null : StringTools.trim(source)
		});
	}

	public static function listCustomMetadataEntries():Array<MacroCustomMetadataSnapshot> {
		final out = new Array<MacroCustomMetadataSnapshot>();
		for (entry in customMetadataEntries)
			out.push({
				metadata: entry.metadata,
				doc: entry.doc,
				source: entry.source
			});
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

	/**
		Seed local macro-context query results for the active compilation.

		Why
		- Runtime macro code may query `Context.getLocalModule()`, `getLocalMethod()`,
		  `getLocalType()`, `getExpectedType()`, or `getCallArguments()` even though the external-host runtime does not
		  have direct access to upstream's live typer structures.
		- A compiler-owned snapshot keeps this surface deterministic without over-claiming general
		  typed reflection support.

		What
		- Stores a conservative local context snapshot using Haxe type text for the type slots.
		- Type text is intentionally narrow and currently expected to match the runtime builtin type
		  helper subset (for example `String`, `Bool`, `Null<String>`, `Dynamic`).
		- Optional local TVars can be seeded for runtime `Context.getLocalTVars()` probes.
		- Optional call-argument expression texts can be seeded for runtime `Context.getCallArguments()`
		  probes and are parsed back through the narrow runtime parser rung.
	**/
	public static function setLocalContext(context:MacroLocalContextSnapshot):Void {
		if (context == null) {
			explicitLocalContext = null;
			return;
		}
		final trimmedModule = context.modulePath == null ? "" : StringTools.trim(context.modulePath);
		explicitLocalContext = {
			modulePath: trimmedModule,
			methodName: normalizeOptionalText(context.methodName),
			localTypeText: normalizeOptionalText(context.localTypeText),
			expectedTypeText: normalizeOptionalText(context.expectedTypeText),
			callArgumentExprTexts: normalizeExprTexts(context.callArgumentExprTexts),
			localTVars: normalizeLocalTVars(context.localTVars)
		};
	}

	public static function clearLocalContext():Void {
		explicitLocalContext = null;
	}

	/**
		Seed a compiler-owned `Context.getMainExpr()` snapshot.

		Why
		- Reflaxe-style compiler helpers may query `Context.getMainExpr()` while running inside the
		  external macro host.
		- The runtime host does not have live access to the compiler's main-expression typing state,
		  so the honest bring-up rung is a compiler-seeded expression snapshot.

		What
		- Stores expression text that the runtime host later reparses through the narrow runtime parser
		  and types through the narrow synthetic typed-expression bridge.

		Gotchas
		- This is intentionally a seeded snapshot, not full live main-expression parity.
		- Expression coverage is limited by `RuntimeMacroExprs` + `RuntimeTypedExprs`.
	**/
	public static function setMainExprText(exprText:String):Void {
		explicitMainExprText = normalizeOptionalText(exprText);
	}

	public static function clearMainExprText():Void {
		explicitMainExprText = null;
	}

	public static function getMainExprText():Null<String> {
		return explicitMainExprText;
	}

	static function normalizeOptionalText(value:Null<String>):Null<String> {
		if (value == null)
			return null;
		final trimmed = StringTools.trim(value);
		return trimmed.length == 0 ? null : trimmed;
	}

	static function normalizeLocalTVars(values:Array<MacroLocalTVarSnapshot>):Array<MacroLocalTVarSnapshot> {
		final out = new Array<MacroLocalTVarSnapshot>();
		if (values == null || values.length == 0)
			return out;
		for (value in values) {
			if (value == null || value.name == null || value.typeText == null)
				continue;
			final name = StringTools.trim(value.name);
			final typeText = StringTools.trim(value.typeText);
			if (name.length == 0 || typeText.length == 0)
				continue;
			final id = value.id == null || value.id <= 0 ? nextSyntheticLocalTVarId++ : value.id;
			out.push({
				name: name,
				typeText: typeText,
				id: id,
				capture: value.capture == true,
				isStatic: value.isStatic == true
			});
		}
		return out;
	}

	static function normalizeExprTexts(values:Array<String>):Array<String> {
		final out = new Array<String>();
		if (values == null || values.length == 0)
			return out;
		for (value in values) {
			if (value == null)
				continue;
			final trimmed = StringTools.trim(value);
			if (trimmed.length == 0)
				continue;
			out.push(trimmed);
		}
		return out;
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

	public static function addMessage(kind:String, msg:String, pos:MacroPositionInfo):Void {
		final trimmedKind = kind == null ? "" : StringTools.trim(kind);
		final trimmedMsg = msg == null ? "" : msg;
		if (trimmedKind.length == 0 || trimmedMsg.length == 0)
			return;
		final snapshotPos:MacroPositionInfo = pos == null ? getCurrentPos() : {
			file: pos.file == null || pos.file.length == 0 ? "<macro>" : pos.file,
			min: pos.min < 0 ? 0 : pos.min,
			max: pos.max < 0 ? 0 : pos.max
		};
		messages.push({
			kind: trimmedKind,
			msg: trimmedMsg,
			pos: snapshotPos
		});
	}

	public static function listMessages():Array<MacroMessageSnapshot> {
		return [
			for (message in messages)
				{
					kind: message.kind,
					msg: message.msg,
					pos: {
						file: message.pos.file,
						min: message.pos.min,
						max: message.pos.max
					}
				}
		];
	}

	public static function replaceMessages(nextMessages:Array<MacroMessageSnapshot>):Void {
		messages.resize(0);
		if (nextMessages == null || nextMessages.length == 0)
			return;
		for (message in nextMessages) {
			if (message == null || message.kind == null || message.msg == null || message.pos == null)
				continue;
			final trimmedKind = StringTools.trim(message.kind);
			if (trimmedKind.length == 0 || message.msg.length == 0)
				continue;
			messages.push({
				kind: trimmedKind,
				msg: message.msg,
				pos: {
					file: message.pos.file == null || message.pos.file.length == 0 ? "<macro>" : message.pos.file,
					min: message.pos.min < 0 ? 0 : message.pos.min,
					max: message.pos.max < 0 ? 0 : message.pos.max
				}
			});
		}
	}

	public static function getLocalModule():String {
		if (explicitLocalContext != null && explicitLocalContext.modulePath != null && explicitLocalContext.modulePath.length > 0)
			return explicitLocalContext.modulePath;
		return definedValue("HXHX_BUILD_MODULE");
	}

	public static function getLocalMethod():Null<String> {
		return explicitLocalContext == null ? null : explicitLocalContext.methodName;
	}

	public static function getLocalTypeText():Null<String> {
		return explicitLocalContext == null ? null : explicitLocalContext.localTypeText;
	}

	public static function getExpectedTypeText():Null<String> {
		return explicitLocalContext == null ? null : explicitLocalContext.expectedTypeText;
	}

	public static function listLocalTVars():Array<MacroLocalTVarSnapshot> {
		if (explicitLocalContext == null || explicitLocalContext.localTVars == null || explicitLocalContext.localTVars.length == 0)
			return [];
		return [
			for (entry in explicitLocalContext.localTVars)
				{
					name: entry.name,
					typeText: entry.typeText,
					id: entry.id,
					capture: entry.capture,
					isStatic: entry.isStatic
				}
		];
	}

	public static function listCallArgumentExprTexts():Array<String> {
		if (explicitLocalContext == null
			|| explicitLocalContext.callArgumentExprTexts == null
			|| explicitLocalContext.callArgumentExprTexts.length == 0)
			return [];
		return explicitLocalContext.callArgumentExprTexts.copy();
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
		  - `onTypeNotFound`
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
			case "onTypeNotFound":
				onTypeNotFoundHookIds.push(id);
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

	public static function listOnTypeNotFoundHookIds():Array<Int> {
		return onTypeNotFoundHookIds.copy();
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
		- Accepts either a simple module name (`Gen`) or a dotted module path (`demo.Gen`).
		- Writes the corresponding `.hx` file under the generated hx directory.
		- Records the module by full module path so tests can assert what was emitted.
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

		// Conservative file-safe module path:
		// [A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*
		inline function isAlpha(c:Int):Bool
			return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code);
		inline function isDigit(c:Int):Bool
			return c >= "0".code && c <= "9".code;
		inline function isUnderscore(c:Int):Bool
			return c == "_".code;
		final segments = n.split(".");
		if (segments.length == 0)
			return;
		for (segment in segments) {
			final s = StringTools.trim(segment);
			if (s.length == 0)
				return;
			final first = s.charCodeAt(0);
			if (!(isAlpha(first) || isUnderscore(first)))
				return;
			for (i in 1...s.length) {
				final c = s.charCodeAt(i);
				if (!(isAlpha(c) || isDigit(c) || isUnderscore(c)))
					return;
			}
		}

		if (!sys.FileSystem.exists(generatedHxDir))
			sys.FileSystem.createDirectory(generatedHxDir);
		var dir = generatedHxDir;
		for (i in 0...segments.length - 1) {
			dir = haxe.io.Path.join([dir, segments[i]]);
			if (!sys.FileSystem.exists(dir))
				sys.FileSystem.createDirectory(dir);
		}
		final path = haxe.io.Path.join([dir, segments[segments.length - 1] + ".hx"]);
		sys.io.File.saveContent(path, source == null ? "" : source);
		generatedHxModules.set(n, source == null ? "" : source);
	}

	public static function hasGeneratedHxModules():Bool {
		for (_ in generatedHxModules.keys())
			return true;
		return false;
	}

	public static function listGeneratedHxModuleNames():Array<String> {
		final out = new Array<String>();
		for (k in generatedHxModules.keys())
			out.push(k);
		sortStringsInPlace(out);
		return out;
	}

	public static function getGeneratedHxModuleSource(modulePath:String):Null<String> {
		if (modulePath == null || modulePath.length == 0)
			return null;
		return generatedHxModules.get(modulePath);
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
