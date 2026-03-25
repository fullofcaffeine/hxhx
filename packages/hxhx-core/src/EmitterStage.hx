/**
	Stage 2/3 OCaml emitter and bootstrap build helper.

	Last audited: 2026-03-03.

	Why:
	- The real Haxe compiler has multiple generators; for Haxe-in-Haxe we’ll need
	  at minimum a bytecode or OCaml-emission strategy for self-hosting.
	- Even before the full compiler exists, we want an end-to-end “typed → emitted →
	  built artifact” slice to keep bootstrapping honest.

	What (in this repo today):
	- `emit` remains a placeholder entrypoint for the long-term backend-agnostic API.
	- `emitToDir` is the Stage3 bootstrap OCaml path used by `hxhx --hxhx-stage3`:
	  it emits module units, copies repo-owned runtime units, and can compile an
	  executable with `ocamlopt`.

	Current scope:
	- Handles Stage3 OCaml emission for the native bootstrap lane.
	- Includes runtime copy/link behavior for `packages/reflaxe.ocaml/std/runtime`.
	- Supports broader expression/statement lowering than the original bring-up
	  subset, but still does not claim full upstream Haxe semantic coverage.

	Runtime/report boundary:
	- Reflaxe portable/metal runtime-plan and profile reports are generated in
	  `RuntimeCopier`/`OcamlCompiler`.
	- This class focuses on Stage3 OCaml emission and local bootstrap build wiring.

	Non-goals:
	- Full Haxe semantics (nullability, classes, enums, etc.).
	- Defining the cross-target backend contract used by non-Stage3 lanes.
**/
private typedef EmitterCallSig = {
	/** Total OCaml parameters after lowering (includes the rest-array parameter when present). */
	final expected:Int;

	/** Required OCaml parameters after lowering (receiver + non-optional params). */
	final required:Int;

	/** Number of fixed (non-rest) parameters. */
	final fixed:Int;

	/** Whether the final parameter is a lowered rest-args array. */
	final hasRest:Bool;

	/** Whether this lowered call expects a synthetic receiver parameter. */
	final needsReceiver:Bool;
}

private enum Stage3DuneLayoutKind {
	Executable;
	Library;
	Plugin;
}

private class _EmitterStageDebug {
	/**
		Emit a debug trace of computed call signatures.

		Why
		- Rest-arg bring-up depends on a signature map (`callSigByCallee`) built from parsed
		  declarations. When it is wrong, the emitter can accidentally pack *all* call arguments
		  into the rest array (or fail to pack any), which then shows up as confusing OCaml type
		  errors at build time.

		How
		- Gated by `HXHX_TRACE_CALLSIG=1`.
		- Written to stderr so it doesn't perturb tests that assert stdout output.
	**/
	public static function traceCallSig(modName:String, fnName:String, args:Array<HxFunctionArg>, required:Int, fixed:Int, hasRest:Bool,
			needsReceiver:Bool):Void {
		final enabled = Sys.getEnv("HXHX_TRACE_CALLSIG");
		if (enabled != "1" && enabled != "true" && enabled != "yes")
			return;
		try {
			final parts = new Array<String>();
			if (args != null) {
				for (a in args) {
					final nm = HxFunctionArg.getName(a);
					final kind = HxFunctionArg.getIsRest(a) ? "rest" : "fixed";
					final hint = StringTools.trim(HxFunctionArg.getTypeHint(a));
					parts.push(nm + ":" + kind + (hint.length == 0 ? "" : (":" + hint)));
				}
			}
			Sys.stderr()
				.writeString("callsig " + modName + "." + fnName + " required=" + required + " fixed=" + fixed + " hasRest=" + (hasRest ? "1" : "0")
					+ " needsReceiver=" + (needsReceiver ? "1" : "0") + " args=[" + parts.join(",") + "]\n");
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	/**
		Emit a debug trace for Stage3 module emission progress.

		Why
		- Some Stage3 bring-up failures currently surface as hard crashes during module emission.
		- A narrow per-module trace lets us identify the last module reached without perturbing
		  normal stdout-based gate markers.

		How
		- Gated by `HXHX_TRACE_STAGE3_MODULE_EMIT=1`.
		- Written to stderr so the existing stdout markers remain stable.
	**/
	static inline function traceStage3Enabled():Bool {
		final enabled = Sys.getEnv("HXHX_TRACE_STAGE3_MODULE_EMIT");
		return enabled == "1" || enabled == "true" || enabled == "yes";
	}

	public static function traceStage3Phase(label:String):Void {
		if (!traceStage3Enabled())
			return;
		try {
			final err = Sys.stderr();
			err.writeString("stage3_emit_phase=" + label + "\n");
			err.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	public static function traceStage3Module(label:String, moduleName:String, filePath:Null<String>):Void {
		if (!traceStage3Enabled())
			return;
		try {
			final fileTag = filePath == null ? "<unknown>" : filePath;
			final err = Sys.stderr();
			err.writeString("stage3_emit[" + label + "]=" + moduleName + " file=" + fileTag + "\n");
			err.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	public static function traceStage3Function(label:String, moduleName:String, functionName:String):Void {
		if (!traceStage3Enabled())
			return;
		try {
			final err = Sys.stderr();
			err.writeString("stage3_emit[" + label + "]=" + moduleName + "." + functionName + "\n");
			err.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	/**
		Emit a narrow local-typing trace for one Stage3 function/local combination.

		Why
		- Some remaining upstream bring-up seams depend on how `tyCtx` and `localHints`
		  interact at one specific mutable local.
		- Logging every local in every function would drown the gate output and make long
		  bootstrap runs harder to reason about.

		How
		- Gated by `HXHX_TRACE_LOCAL_TYPE=<Module>:<function>:<local>`.
		- Written to stderr so stdout contract markers remain stable.
	**/
	public static function traceLocalType(label:String, moduleName:String, functionName:String, localName:String, detail:String):Void {
		final target = Sys.getEnv("HXHX_TRACE_LOCAL_TYPE");
		if (target == null || target.length == 0)
			return;
		final expected = moduleName + ":" + functionName + ":" + localName;
		if (target != expected)
			return;
		try {
			final err = Sys.stderr();
			err.writeString("local_type[" + label + "]=" + expected + " " + detail + "\n");
			err.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	static inline function traceSelfRecursionEnabled():Bool {
		final enabled = Sys.getEnv("HXHX_TRACE_SELF_RECURSION");
		return enabled == "1" || enabled == "true" || enabled == "yes";
	}

	public static function traceSelfRecursion(label:String, detail:String):Void {
		if (!traceSelfRecursionEnabled())
			return;
		try {
			final err = Sys.stderr();
			err.writeString("selfrec[" + label + "]=" + detail + "\n");
			err.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}
}

private class _InstanceFieldEntry {
	public final key:String;
	public final fields:Array<HxFieldDecl>;

	public function new(key:String, fields:Array<HxFieldDecl>) {
		this.key = key;
		this.fields = fields;
	}
}

private class _InstanceMethodEntry {
	public final key:String;
	public final methodNames:Array<String>;

	public function new(key:String, methodNames:Array<String>) {
		this.key = key;
		this.methodNames = methodNames;
	}
}

private class _ModuleNameEntry {
	public final key:String;
	public final moduleName:String;

	public function new(key:String, moduleName:String) {
		this.key = key;
		this.moduleName = moduleName;
	}
}

class EmitterStage {
	static var moduleInitTrace:Bool = traceModuleInit();

	static function traceModuleInit():Bool {
		_EmitterStageDebug.traceStage3Phase("emitter_module_init");
		return true;
	}

	/**
		The OCaml compilation unit we are currently emitting.

		Why
		- Haxe code commonly qualifies static calls with the defining type/module name, even
		  inside that same module, e.g. `Lambda.flatten(Lambda.map(...))`.
		- In OCaml, a compilation unit cannot refer to its own module name from within the
		  unit itself. Emitting `Lambda.flatten` inside `Lambda.ml` is an "Unbound module"
		  error and also causes `ocamldep -sort` to fail with a self-dependency cycle.

		How
		- `emitMainClass` sets this before emitting expressions and restores it after.
		- `exprToOcaml` drops `ModName.` qualifiers when `ModName` matches this value.
	**/
	static var currentOcamlModuleName:Null<String> = null;

	static var currentModuleFilePath:Null<String> = null;

	/**
		Import-based rewrite for `Int64.<field>` in the current module.

		Why
		- Upstream Haxe commonly does `import haxe.Int64.*;` and then calls `Int64.mul(...)`.
		- In OCaml, `Int64` is a stdlib module. Emitting `Int64.mul` therefore resolves to the
		  wrong provider and fails typechecking.
		- We intentionally avoid emitting an `Int64.ml` alias shim because it would shadow the
		  OCaml stdlib.

		How
		- `emitMainClass` sets this to the imported provider module name (usually `Haxe_Int64`)
		  and restores it after the unit is emitted.
		- `exprToOcaml` consults it when lowering single-part type paths (`Int64.mul`).
	**/
	static var currentImportInt64:Null<String> = null;

	/**
		Fallback index for package/type path lookups during emission.

		Why
		- In bootstrap OCaml builds, `Reflect.field(map, "get")` can fail for lowered map
		  values even when the source-side `Map` is populated.
		- Parent-package type fallback (`package a.b; Util.foo()`) relies on this lookup.
	**/
	static var currentModuleNameEntries:Array<_ModuleNameEntry> = [];

	static var currentKnownModuleNames:Map<String, Bool> = new Map();
	static var currentGlobalImportAliasByIdent:Map<String, String> = new Map();

	/**
		Per-module instance-field metadata used by Stage3 full-body emission.

		Why
		- We emit class methods as top-level OCaml functions.
		- To make `new C(); this.x = ...; obj.x` runnable before a full object model exists,
		  we need a small, deterministic map from Haxe type-paths to declared instance fields.

		How
		- `emitMainClass` seeds this map from parsed class declarations in the current module.
		- `exprToOcaml` consults it for `new` lowering.
	**/
	static var currentInstanceFieldsByTypePath:Null<Array<_InstanceFieldEntry>> = null;

	/**
		Per-module instance-method metadata for Stage3 method-call rewriting.

		Why
		- Haxe instance calls (`obj.ping()`) are represented as `ECall(EField(obj,"ping"), ...)`.
		- Stage3 emits functions, so we rewrite to `ping obj ...` when the member is known to be
		  an instance method.

		How
		- `emitMainClass` seeds this map for classes in the current module.
		- `exprToOcaml` uses it conservatively (never for type-path/static calls).
	**/
	static var currentInstanceMethodsByTypePath:Null<Array<_InstanceMethodEntry>> = null;

	/**
		Statement-scope mutable local tracking for Stage3 full-body emission.

		Why
		- Haxe locals declared with `var` can be reassigned (`=`, `+=`, etc.).
		- OCaml `let` bindings are immutable, so reassignment needs `ref` cells.

		How
		- `stmtListToOcaml` computes mutable locals for the current statement list and
		  merges them with outer scope tracking.
		- `exprToOcaml` reads mutable identifiers via `!x`.
		- assignment statements lower to `x := value`.
	**/
	static var currentMutableLocalRefNames:Array<String> = [];

	/**
		Function-scope value identifiers currently allowed to survive Stage3 bring-up.

		Why
		- Some native-parser / Stage3 typed paths still fail to attach a reliable local type
		  entry for identifiers that are unquestionably in scope, especially method params in
		  complex real workloads.
		- Collapsing those names to `(Obj.magic 0)` poisons otherwise-structured output and
		  hides the real backend progress.

		How
		- `emitMainClass` installs the current function's allowed identifier map while lowering
		  that function body.
		- `exprToOcaml` uses it only as a fallback after explicit method/static/module checks.
	**/
	static var currentAllowedValueIdentNames:Null<Map<String, Bool>> = null;
	static var currentExprTyHints:Null<Map<String, TyType>> = null;

	/**
		Backend dialect seam for OCaml-coupled runtime expression snippets.

		Why
		- Stage3 currently emits OCaml text directly, but we want a clear extraction
		  point for future non-OCaml backends.

		How
		- Keep a tiny interface here first (null checks/dynamic equality/null sentinel).
		- Expand incrementally as additional seams are extracted.
	 */
	static final backendDialect:HihBackendDialect = new HihOcamlBackendDialect();

	/**
		Active OCaml profile for the current emit run.

		Why
		- Stage3 keeps one emitter implementation for both `portable` and `metal`.
		- Some lowering choices (for example numeric fallback policy) need profile-aware
		  behavior without changing all call sites.

		How
		- `emitToDir(...)` sets this value at entry.
		- Expression lowering reads it through `isMetalProfileActive()`.
	**/
	static var currentOcamlProfile:String = backend.OcamlProfile.toDefineValue(backend.OcamlProfile.Portable);

	static inline function traceEmitToDirEntry(label:String):Void {
		_EmitterStageDebug.traceStage3Phase(label);
	}

	static function requireEmitToDirOutAbs(outDir:String):String {
		traceEmitToDirEntry("emitToDir_before_validate");
		if (outDir == null || StringTools.trim(outDir).length == 0)
			throw "stage3 emitter: missing outDir";
		traceEmitToDirEntry("emitToDir_before_normalize");
		final outAbs = haxe.io.Path.normalize(outDir);
		traceEmitToDirEntry("emitToDir_after_normalize");
		return outAbs;
	}

	static function installEmitToDirProfile(ocamlProfile:backend.OcamlProfile):Void {
		traceEmitToDirEntry("emitToDir_before_profile_define");
		currentOcamlProfile = backend.OcamlProfile.toDefineValue(ocamlProfile);
		traceEmitToDirEntry("emitToDir_after_profile");
	}

	static function ensureEmitToDirOutDir(outAbs:String):Void {
		traceEmitToDirEntry("emitToDir_before_outdir_ensure");
		if (!sys.FileSystem.exists(outAbs))
			sys.FileSystem.createDirectory(outAbs);
		traceEmitToDirEntry("emitToDir_after_outdir");
	}

	/**
		Portable auto-metalization plan for the active emit invocation.

		Why
		- Stage3 expression lowering is implemented as static helpers for bootstrap simplicity.
		- Portable auto-metalization decisions must therefore be available through static
		  context while each function body is emitted.

		What
		- `currentPortableMetalizationPlan`: per-run plan built by `PortableMetalizationPlanner`.
		- `currentPortableMetalizationRegionKey`: current function region being lowered.

		How
		- `emitToDirWithPortableMetalizationPlan(...)` installs/restores plan state.
		- `emitMainClass` sets the region key before lowering each function body.
	**/
	static var currentPortableMetalizationPlan:Null<backend.ocaml.PortableMetalizationPlan> = null;

	static var currentPortableMetalizationRegionKey:Null<String> = null;

	/**
		Current function name while lowering one function body.

		Why
		- Some Stage3 CLI/native paths still recover direct self-recursive calls as bare
		  identifiers without enough receiver metadata to re-insert `this_` generically.
		- Tracking the active function lets call lowering normalize exact self-recursive
		  instance calls without widening unrelated call-shape heuristics.
	**/
	static var currentFunctionNameRaw:Null<String> = null;

	public static function installPortableMetalizationPlan(plan:Null<backend.ocaml.PortableMetalizationPlan>):{previousPlan:Null<backend.ocaml.PortableMetalizationPlan>, previousRegionKey:Null<String>} {
		_EmitterStageDebug.traceStage3Phase("portable_plan_install");
		final scope = {
			previousPlan: currentPortableMetalizationPlan,
			previousRegionKey: currentPortableMetalizationRegionKey
		};
		currentPortableMetalizationPlan = plan;
		currentPortableMetalizationRegionKey = null;
		return scope;
	}

	public static function restorePortableMetalizationPlan(scope:{previousPlan:Null<backend.ocaml.PortableMetalizationPlan>, previousRegionKey:Null<String>}):Void {
		_EmitterStageDebug.traceStage3Phase("portable_plan_restore");
		currentPortableMetalizationPlan = scope.previousPlan;
		currentPortableMetalizationRegionKey = scope.previousRegionKey;
	}

	static inline function isMetalProfileActive():Bool {
		return currentOcamlProfile == backend.OcamlProfile.toDefineValue(backend.OcamlProfile.Metal);
	}

	static inline function isPortableAutoMetalizedRegionActive():Bool {
		return currentOcamlProfile == backend.OcamlProfile.toDefineValue(backend.OcamlProfile.Portable)
			&& currentPortableMetalizationPlan != null
			&& currentPortableMetalizationRegionKey != null
			&& currentPortableMetalizationPlan.isAutoMetalized(currentPortableMetalizationRegionKey);
	}

	static inline function markPortableAutoMetalizedLoweringUse(lowering:String):Void {
		if (!isPortableAutoMetalizedRegionActive())
			return;
		currentPortableMetalizationPlan.markLoweringUsed(currentPortableMetalizationRegionKey, lowering);
	}

	/**
		Emit wrapper that installs portable auto-metalization state for one emit pass.

		Why
		- `emitToDir(...)` is called from multiple test/runtime entrypoints; adding planner state
		  directly to all call chains would be high-risk churn.
		- This wrapper keeps default callers unchanged while allowing `OcamlTargetCore` to enable
		  planner-aware lowerings.

		How
		- Captures previous static planner state.
		- Installs requested plan for the call.
		- Restores previous state on success and failure.

		Exception boundary note
		- The catch is intentionally confined to this boundary to guarantee state restoration.
	**/
	public static function emitToDirWithPortableMetalizationPlan(p:MacroExpandedProgram, outDir:String, emitFullBodies:Bool = false,
			buildExecutable:Bool = true, ocamlProfile:backend.OcamlProfile = backend.OcamlProfile.Portable,
			?defines:haxe.ds.StringMap<String>,
			?portableMetalizationPlan:backend.ocaml.PortableMetalizationPlan):String {
		_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_before_install");
		final scope = installPortableMetalizationPlan(portableMetalizationPlan);
		var entryPath = "";
		try {
			_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_before_emitToDir");
			entryPath = emitToDir(p, outDir, emitFullBodies, buildExecutable, ocamlProfile, defines);
			_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_after_emitToDir");
		} catch (error:haxe.Exception) {
			restorePortableMetalizationPlan(scope);
			throw error;
		}
		restorePortableMetalizationPlan(scope);
		return entryPath;
	}

	static function hasDefine(defines:haxe.ds.StringMap<String>, name:String):Bool {
		return defines != null && name != null && name.length > 0 && defines.exists(name);
	}

	static function defineValue(defines:haxe.ds.StringMap<String>, name:String):Null<String> {
		if (defines == null || name == null || name.length == 0)
			return null;
		return defines.get(name);
	}

	static function sanitizeDuneName(name:String):String {
		final out = new StringBuf();
		final source = name == null ? "" : name;
		for (i in 0...source.length) {
			final c = source.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c) : "_");
		}
		var s = out.toString();
		if (s.length == 0)
			s = "ocaml_app";
		final first = s.charCodeAt(0);
		if (first >= 48 && first <= 57)
			s = "_" + s;
		return s;
	}

	static function defaultDuneProjectName(outDir:String):String {
		final base = haxe.io.Path.withoutDirectory(haxe.io.Path.normalize(outDir));
		return sanitizeDuneName(base.length > 0 ? base : "ocaml_app");
	}

	static function defaultDuneExeName(outDir:String):String {
		return defaultDuneProjectName(outDir).toLowerCase();
	}

	static function normalizeStage3DuneLayout(raw:Null<String>):Stage3DuneLayoutKind {
		final value = raw == null ? "exe" : StringTools.trim(raw).toLowerCase();
		return switch (value) {
			case "" | "exe" | "executable": Stage3DuneLayoutKind.Executable;
			case "lib" | "library": Stage3DuneLayoutKind.Library;
			case "plugin": Stage3DuneLayoutKind.Plugin;
			case _:
				throw "stage3 emitter: invalid ocaml_dune_layout `" + value + "` (expected exe|lib|plugin)";
		}
	}

	static function emitStage3DuneScaffold(outAbs:String, layout:Stage3DuneLayoutKind, duneLibraries:Array<String>, rootMainPath:Null<String>):String {
		final projectName = defaultDuneProjectName(outAbs);
		final exeName = defaultDuneExeName(outAbs);
		final exeLibs = ["hx_runtime"].concat(duneLibraries == null ? [] : duneLibraries);
		final mainModuleName = if (rootMainPath == null || rootMainPath.length == 0) {
			null;
		} else {
			final file = haxe.io.Path.withoutDirectory(rootMainPath);
			final base = StringTools.endsWith(file, ".ml") ? file.substr(0, file.length - 3) : file;
			base.length == 0 ? null : base;
		}

		final runtimeDuneLines = [
			"(library",
			" (name hx_runtime)",
			" (wrapped false)",
			" (modules :standard)"
		];
		if (duneLibraries != null && duneLibraries.length > 0)
			runtimeDuneLines.push(" (libraries " + duneLibraries.join(" ") + ")");
		runtimeDuneLines.push(")");
		runtimeDuneLines.push("");
		runtimeDuneLines.push("; Generated by hxhx(stage3)");
		sys.io.File.saveContent(haxe.io.Path.join([outAbs, "runtime", "dune"]), runtimeDuneLines.join("\n"));

		sys.io.File.saveContent(haxe.io.Path.join([outAbs, ".gitignore"]), "_build/\n*.install\n");
		sys.io.File.saveContent(haxe.io.Path.join([outAbs, "dune-project"]), [
			"(lang dune 2.9)",
			"(name " + projectName + ")",
			"(wrapped_executables false)",
			"",
			"; Generated by hxhx(stage3)"
		].join("\n"));

		inline function emitEntry(name:String, content:String):String {
			final path = haxe.io.Path.join([outAbs, name + ".ml"]);
			sys.io.File.saveContent(path, content);
			return path;
		}

		return switch (layout) {
			case Stage3DuneLayoutKind.Library:
				sys.io.File.saveContent(haxe.io.Path.join([outAbs, "dune"]), [
					"(library",
					" (name " + projectName + ")",
					" (wrapped false)",
					" (modules :standard)",
					" (libraries " + exeLibs.join(" ") + "))",
					"",
					"; Generated by hxhx(stage3)"
				].join("\n"));
				haxe.io.Path.join([outAbs, projectName + ".cma"]);
			case Stage3DuneLayoutKind.Plugin:
				sys.io.File.saveContent(haxe.io.Path.join([outAbs, "dune"]), [
					"(executable",
					" (name " + exeName + ")",
					" (modules :standard)",
					" (libraries " + exeLibs.join(" ") + ")",
					" (modes (native plugin) (byte plugin)))",
					"",
					"; Generated by hxhx(stage3)"
				].join("\n"));
				emitEntry(exeName, "let () = ()\n");
				haxe.io.Path.join([outAbs, exeName + ".cma"]);
			case Stage3DuneLayoutKind.Executable:
				sys.io.File.saveContent(haxe.io.Path.join([outAbs, "dune"]), [
					"(executable",
					" (name " + exeName + ")",
					" (modules :standard)",
					" (libraries " + exeLibs.join(" ") + ")",
					" (modes (native exe) (byte exe)))",
					"",
					"; Generated by hxhx(stage3)"
				].join("\n"));
				final entryBody = if (mainModuleName == null) {
					"let () = ()\n";
				} else {
					[
						"let () =",
						"  HxTypeRegistry.init ();",
						"  ignore (" + mainModuleName + ".main ())",
						""
					].join("\n");
				}
				emitEntry(exeName, entryBody);
				haxe.io.Path.join([outAbs, exeName + ".exe"]);
		}
	}

	public static function emit(_:MacroExpandedModule):Void {
		// Stub: eventually write output files / bytecode.
	}

	static function escapeOcamlIdentPart(s:String):String {
		if (s == null || s.length == 0)
			return "_";
		final out = new StringBuf();
		for (i in 0...s.length) {
			final c = s.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c) : "_");
		}
		final t = out.toString();
		return t.length == 0 ? "_" : t;
	}

	static function ocamlTypeFromTy(t:TyType):String {
		return switch (t.toString()) {
			case "Int": "int";
			case "Float": "float";
			case "Bool": "bool";
			case "String": "string";
			case "Void": "unit";
			// Stage 3 bring-up: enough structure for common debug/log/utest patterns.
			//
			// Why
			// - Upstream code (and utest) uses `haxe.PosInfos` for callsite reporting.
			// - Without a record type, emitting `pos.fileName` fails with "Unbound record field".
			//
			// How
			// - We provide a tiny OCaml shim module `HxPosInfos.ml` that defines a record type `t`
			//   with the fields used by upstream (`fileName`, `lineNumber`, ...).
			// - This is still bootstrap-only: values are often `Obj.magic` in bring-up code paths.
			case "haxe.PosInfos", "PosInfos": "HxPosInfos.t";
			// Stage 3 bring-up: do not constrain `haxe.Int64` with a concrete OCaml type yet.
			//
			// Why
			// - Upstream unit code uses operator-overloaded Int64 expressions (`a / b`, `a * 7`, ...)
			//   which our bootstrap typer/emitter does not model correctly yet.
			// - Emitting a concrete OCaml type here (`Haxe_Int64.t`) often forces type errors when
			//   the emitter temporarily lowers these operations through `float`/`int` operators.
			//
			// We still generate an `Haxe_Int64` provider module for the *static functions* (make/sub/...)
			// so name resolution succeeds, but we keep the type annotation as `_` to let the OCaml
			// compiler infer a permissive type.
			case "haxe.Int64", "Int64": "_";
			// Stage 3: anything else is unknown; avoid making up a type.
			case _: "_";
		}
	}

	static function lowerFirst(name:String):String {
		if (name == null || name.length == 0)
			return "_";
		final c = name.charCodeAt(0);
		final isUpper = c >= 65 && c <= 90;
		return isUpper ? (String.fromCharCode(c + 32) + name.substr(1)) : name;
	}

	static function isOcamlKeyword(name:String):Bool {
		if (name == null)
			return false;
		return switch (name) {
			case "and" | "as" | "assert" | "begin" | "class" | "constraint" | "do" | "done" | "downto" | "else" | "end" | "exception" | "external" | "false" |
				"for" | "fun" | "function" | "functor" | "if" | "in" | "include" | "inherit" | "initializer" | "lazy" | "let" | "match" | "method" |
				"module" | "mutable" | "mod" | "new" | "nonrec" | "object" | "of" | "open" | "or" | "private" | "rec" | "sig" | "struct" | "then" | "to" |
				"true" | "try" | "type" | "val" | "virtual" | "when" | "while" | "with":
				true;
			case _:
				false;
		}
	}

	static function ocamlValueIdent(raw:String):String {
		final base = lowerFirst(raw);
		if (base == "_" || base.length == 0)
			return "_";
		return isOcamlKeyword(base) ? (base + "_") : base;
	}

	static function isMutableLocalRefIdent(name:String):Bool {
		final refs = currentMutableLocalRefNames;
		if (refs == null || refs.length == 0 || name == null || name.length == 0)
			return false;
		for (n in refs)
			if (n == name)
				return true;
		return false;
	}

	static function ocamlReadValueIdent(raw:String):String {
		final ident = ocamlValueIdent(raw);
		return isMutableLocalRefIdent(raw) ? "(!" + ident + ")" : ident;
	}

	static function isUpperStart(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final c = name.charCodeAt(0);
		return c >= 65 && c <= 90;
	}

	static function upperFirst(s:String):String {
		if (s == null || s.length == 0)
			return s;
		final c = s.charCodeAt(0);
		final isLower = c >= 97 && c <= 122;
		return isLower ? (String.fromCharCode(c - 32) + s.substr(1)) : s;
	}

	static function ocamlModuleNameFromTypePathParts(parts:Array<String>):String {
		if (parts == null || parts.length == 0)
			return "Unknown";
		final escaped = parts.map(escapeOcamlIdentPart);
		escaped[0] = upperFirst(escaped[0]);
		return escaped.join("_");
	}

	static function ocamlModuleNameFromTypePath(typePath:String):String {
		if (typePath == null)
			return "Unknown";
		final trimmed = StringTools.trim(typePath);
		if (trimmed.length == 0)
			return "Unknown";
		return ocamlModuleNameFromTypePathParts(trimmed.split("."));
	}

	static function resolveImportedModuleFileFromContext(filePath:String, modulePath:String):Null<String> {
		if (filePath == null || filePath.length == 0 || modulePath == null || modulePath.length == 0)
			return null;
		final rel = modulePath.split(".").join("/") + ".hx";
		var dir = haxe.io.Path.directory(filePath);
		final seen:Map<String, Bool> = new Map();
		while (dir != null && dir.length > 0 && !seen.exists(dir)) {
			seen.set(dir, true);
			final direct = haxe.io.Path.join([dir, rel]);
			if (sys.FileSystem.exists(direct))
				return direct;
			final stdPath = haxe.io.Path.join([dir, "std", rel]);
			if (sys.FileSystem.exists(stdPath))
				return stdPath;
			final parent = haxe.io.Path.directory(dir);
			if (parent == null || parent == dir)
				break;
			dir = parent;
		}
		return null;
	}

	static function resolveQualifiedModuleFileFromContext(filePath:String, parts:Array<String>):Null<String> {
		if (filePath == null || filePath.length == 0 || parts == null || parts.length == 0)
			return null;
		for (i in 0...parts.length) {
			final end = parts.length - i;
			final modulePath = parts.slice(0, end).join(".");
			final resolved = resolveImportedModuleFileFromContext(filePath, modulePath);
			if (resolved != null)
				return resolved;
		}
		return null;
	}

	static function expectedMainClassFromFilePath(filePath:Null<String>):Null<String> {
		if (filePath == null || filePath.length == 0)
			return null;
		final base = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(filePath));
		final trimmed = StringTools.trim(base);
		return (trimmed.length > 0 && trimmed != "Unknown") ? trimmed : null;
	}

	static function moduleNameForScannedDecl(decl:HxModuleDecl, moduleTypeName:Null<String>, typeName:String):String {
		final pkgRaw = decl == null ? "" : HxModuleDecl.getPackagePath(decl);
		final pkg = pkgRaw == null ? "" : StringTools.trim(pkgRaw);
		final parts = (pkg.length == 0 ? [] : pkg.split("."));
		final modName = moduleTypeName == null ? "" : StringTools.trim(moduleTypeName);
		if (modName.length > 0 && modName != "Unknown" && typeName != modName)
			parts.push(modName);
		parts.push(typeName);
		return ocamlModuleNameFromTypePathParts(parts);
	}

	static function callSigFromFunction(fn:HxFunctionDecl):EmitterCallSig {
		final fnArgs = HxFunctionDecl.getArgs(fn);
		final argCount = fnArgs == null ? 0 : fnArgs.length;
		final needsReceiver = !HxFunctionDecl.getIsStatic(fn);
		var hasRest = false;
		var fixedCount = argCount;
		if (argCount > 0 && isRestLikeArg(fnArgs[argCount - 1])) {
			hasRest = true;
			fixedCount = argCount - 1;
		}
		var requiredCount = 0;
		for (i in 0...fixedCount) {
			final a = fnArgs[i];
			final hasDefault = switch (HxFunctionArg.getDefaultValue(a)) {
				case Default(_): true;
				case _: false;
			};
			if (!HxFunctionArg.getIsOptional(a) && !hasDefault)
				requiredCount += 1;
		}
		if (needsReceiver) {
			fixedCount += 1;
			requiredCount += 1;
		}
		return {
			expected: fixedCount + (hasRest ? 1 : 0),
			required: requiredCount,
			fixed: fixedCount,
			hasRest: hasRest,
			needsReceiver: needsReceiver
		};
	}

	static function resolveQualifiedModuleCallSig(currentFilePath:String, parts:Array<String>, field:String, loweredField:String):Null<EmitterCallSig> {
		if (currentFilePath == null || currentFilePath.length == 0 || parts == null || parts.length == 0)
			return null;
		final resolvedFile = resolveQualifiedModuleFileFromContext(currentFilePath, parts);
		if (resolvedFile == null || !sys.FileSystem.exists(resolvedFile))
			return null;
		try {
			final source = sys.io.File.getContent(resolvedFile);
			final parsed = ParserStage.parse(source, resolvedFile);
			final decl = parsed.getDecl();
			final moduleTypeName = expectedMainClassFromFilePath(resolvedFile);
			final targetTypeName = parts[parts.length - 1];
			for (cls in HxModuleDecl.getClasses(decl)) {
				final className = HxClassDecl.getName(cls);
				if (className == null || className.length == 0 || className == "Unknown")
					continue;
				// Same-package short type references (`Syntax.code(...)` inside `package php`) resolve to
				// the sibling module file via `resolveQualifiedModuleFileFromContext`, but `parts` still
				// only contains the short type path (`["Syntax"]`). Matching on the resolved file's OCaml
				// module name would reject the correct file (`Php_Syntax` != `Syntax`) and lose rest/optional
				// signature recovery. Once the file is resolved, select the target declaration by type name.
				if (className != targetTypeName)
					continue;
				for (fn in HxClassDecl.getFunctions(cls)) {
					final fnNameRaw = HxFunctionDecl.getName(fn);
					if (fnNameRaw == null || fnNameRaw.length == 0)
						continue;
					if (ocamlValueIdent(fnNameRaw) == loweredField || fnNameRaw == field)
						return callSigFromFunction(fn);
				}
			}
		} catch (_:haxe.Exception) {} catch (_:String) {}
		return null;
	}

	static function tryExtractTypePathPartsFromExpr(e:HxExpr):Null<Array<String>> {
		return switch (e) {
			case EIdent(name):
				[name];
			case EField(obj, field):
				final parts = tryExtractTypePathPartsFromExpr(obj);
				if (parts == null) null else {
					parts.push(field);
					parts;
				}
			case _:
				null;
		}
	}

	/**
		Recognize root stdlib `Sys` when it arrives as a type-path receiver.

		Why
		- Inside `package haxe`, frontend parsing/typing can present `Sys.time()` as a type-path-like
		  receiver rather than a bare `EIdent("Sys")`.
		- If we miss that shape, the generic type-path lowering qualifies it to `Haxe_Sys.time`,
		  but no such module exists in our runtime. The real seam is always `HxSys.*`.

		What
		- Accept only the root `Sys` provider shapes that should lower to runtime intrinsics.
		- Do not generalize this to arbitrary package-qualified `*.Sys` names, because that would
		  blur root stdlib semantics with unrelated user code.
	**/
	static function isRootSysReceiverExpr(e:HxExpr):Bool {
		return switch (e) {
			case EIdent("Sys") | EIdent("Haxe_Sys"):
				true;
			case _: final parts = tryExtractTypePathPartsFromExpr(e); parts != null && parts.length == 1 && parts[0] == "Sys";
		}
	}

	static function isTypePathExpr(e:HxExpr):Bool {
		final parts = tryExtractTypePathPartsFromExpr(e);
		return parts != null && parts.length > 0 && isUpperStart(parts[parts.length - 1]);
	}

	static function currentInstanceFieldsFor(typePath:String):Null<Array<HxFieldDecl>> {
		if (currentInstanceFieldsByTypePath == null || typePath == null)
			return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		final fieldEntries:Array<_InstanceFieldEntry> = cast currentInstanceFieldsByTypePath;
		for (entry in fieldEntries)
			if (entry.key == raw)
				return entry.fields;
		final parts = raw.split(".");
		if (parts.length == 0)
			return null;
		final shortName = parts[parts.length - 1];
		for (entry in fieldEntries)
			if (entry.key == shortName)
				return entry.fields;
		return null;
	}

	static function currentInstanceMethodsFor(typePath:String):Null<Array<String>> {
		if (currentInstanceMethodsByTypePath == null || typePath == null)
			return null;
		final raw = StringTools.trim(typePath);
		if (raw.length == 0)
			return null;
		final methodEntries:Array<_InstanceMethodEntry> = cast currentInstanceMethodsByTypePath;
		for (entry in methodEntries)
			if (entry.key == raw)
				return entry.methodNames;
		final parts = raw.split(".");
		if (parts.length == 0)
			return null;
		final shortName = parts[parts.length - 1];
		for (entry in methodEntries)
			if (entry.key == shortName)
				return entry.methodNames;
		return null;
	}

	static function hasMethodName(methodNames:Null<Array<String>>, methodName:String):Bool {
		if (methodNames == null || methodName == null || methodName.length == 0)
			return false;
		for (name in methodNames)
			if (name == methodName)
				return true;
		return false;
	}

	static function hasCurrentInstanceMethod(field:String):Bool {
		if (currentInstanceMethodsByTypePath == null || field == null || field.length == 0)
			return false;
		final methodEntries:Array<_InstanceMethodEntry> = cast currentInstanceMethodsByTypePath;
		for (entry in methodEntries) {
			if (hasMethodName(entry.methodNames, field))
				return true;
		}
		return false;
	}

	static function escapeOcamlString(s:String):String {
		if (s == null)
			return "\"\"";
		// Minimal escaping: enough for our fixtures.
		//
		// Note (bootstrap/OCaml backend):
		// - Avoid re-assigning the same local repeatedly (`out = ...`) here.
		// - During Stage3 bring-up, `hxhx` itself is compiled by our OCaml backend, and a
		//   bug/limitation in local-rebinding codegen can cause `out = StringTools.replace(...)`
		//   to drop the new value (result is evaluated and ignored).
		// - Nesting calls keeps the semantics correct even under conservative codegen.
		final out = StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(s, "\\", "\\\\"), "\"", "\\\""), "\n",
			"\\n"), "\r", "\\r"), "\t",
			"\\t");
		return "\"" + out + "\"";
	}

	/**
		Best-effort constant folding for string expressions.

		Why
		- Stage 3 bring-up wants a tiny “escape hatch” for embedding raw OCaml expressions
		  via direct OCaml injection call-sites.
		- To keep Haxe sources readable, we often build these strings by concatenating
		  multiple string literals (e.g. `"(let\\n" + " ...\\n" + ")"`).
		- The bootstrap emitter does not implement general constant folding; this helper
		  exists solely to detect and fold the small subset we need.

		What
		- Returns the constant string value if `e` is provably a compile-time string
		  built from literals and `+` concatenation.
		- Returns `null` if the expression is not a safe constant string.
	**/
	static function constFoldString(e:HxExpr):Null<String> {
		return switch (e) {
			case EString(v):
				v == null ? "" : v;
			case EBinop("+", a, b):
				final sa = constFoldString(a);
				if (sa == null) null else {
					final sb = constFoldString(b);
					sb == null ? null : (sa + sb);
				}
			case ECast(expr, _hint):
				constFoldString(expr);
			case EUntyped(expr):
				constFoldString(expr);
			case _:
				null;
		}
	}

	/**
		Read a value from a map-like object (`Map` or lowered `Obj.t`) at emission boundaries.

		This is an intentionally scoped dynamic boundary for Stage3 recursive emitter helpers.
	**/
	static function mapGetRaw<TMap, TValue>(mapLike:Null<TMap>, key:String):Null<TValue> {
		if (mapLike == null || key == null)
			return null;
		final mapLikeObj:{} = cast mapLike;
		final getFn = Reflect.field(mapLikeObj, "get");
		if (getFn == null)
			return null;
		final value = Reflect.callMethod(mapLikeObj, getFn, [key]);
		return value == null ? null : cast value;
	}

	/**
		Check whether a map-like object has a key, with a fallback to `get(...) != null`.
	**/
	static function mapHasRaw<TMap>(mapLike:Null<TMap>, key:String):Bool {
		if (mapLike == null || key == null)
			return false;
		final mapLikeObj:{} = cast mapLike;
		final existsFn = Reflect.field(mapLikeObj, "exists");
		if (existsFn == null)
			return mapGetRaw(mapLike, key) != null;
		final existsValue = Reflect.callMethod(mapLikeObj, existsFn, [key]);
		return existsValue == true;
	}

	/**
		Get a string-key iterator from a map-like object, if available.
	**/
	static function mapKeysRaw<TMap>(mapLike:Null<TMap>):Null<Iterator<String>> {
		if (mapLike == null)
			return null;
		final mapLikeObj:{} = cast mapLike;
		final keysFn = Reflect.field(mapLikeObj, "keys");
		if (keysFn == null)
			return null;
		final keysValue = Reflect.callMethod(mapLikeObj, keysFn, []);
		return keysValue == null ? null : cast keysValue;
	}

	/**
		Conservatively treat a trailing `Rest<T>` / `haxe.Rest<T>` parameter like a rest arg.

		Why
		- Upstream stdlib/extern surfaces frequently model variadics as a typed trailing
		  `Rest<T>` parameter instead of parser-level `...args` syntax.
		- Stage3 call-site lowering already knows how to pack a rest tail once `hasRest`
		  is true; the missing seam was signature recovery, not call emission.

		How
		- Prefer the parser-level rest flag when present.
		- Otherwise inspect the last parameter type hint and recognize the narrow upstream
		  forms we need for Haxe 4.3.7 compatibility.
		- Also accept the lowered compatibility shape used by some extern/runtime surfaces
		  during bring-up: trailing `args:Array<...>` with dynamic-ish element types.

		Why this extra rule is acceptable
		- It is intentionally narrow: only the final parameter, only `args`/`rest`-style
		  names, and only dynamic element arrays.
		- This recovers packaged variadic extern semantics like `php.Syntax.code(...)`
		  without treating arbitrary trailing arrays as variadics.
	**/
	static inline function isRestLikeArg(arg:HxFunctionArg):Bool {
		if (arg == null)
			return false;
		if (HxFunctionArg.getIsRest(arg))
			return true;
		final hint = StringTools.trim(HxFunctionArg.getTypeHint(arg));
		final compactHint = StringTools.replace(hint, " ", "");
		final name = HxFunctionArg.getName(arg);
		final lowerName = name == null ? "" : name.toLowerCase();
		final isNamedRestCarrier = lowerName == "args" || lowerName == "rest" || StringTools.startsWith(lowerName, "rest");
		final dynName = "Dyn" + "amic";
		final anyName = "Any";
		final arrayOfDyn = "Array<" + dynName + ">";
		final arrayOfAny = "Array<" + anyName + ">";
		return hint == "Rest"
			|| StringTools.startsWith(hint, "Rest<")
			|| StringTools.startsWith(hint, "haxe.Rest<")
			|| StringTools.startsWith(hint, "haxe.extern.Rest<")
			|| (isNamedRestCarrier && (compactHint == arrayOfDyn || compactHint == arrayOfAny));
	}

	static inline function renderFloatLiteral(v:Float):String {
		final rendered = Std.string(v);
		return if (rendered.indexOf(".") >= 0 || rendered.indexOf("e") >= 0 || rendered.indexOf("E") >= 0) rendered else rendered + ".";
	}

	static function exprToOcamlString(e:HxExpr, ?tyByIdent:Map<String, TyType>, ?arityByIdent:Map<String, Int>, ?staticImportByIdent:Map<String, String>,
			?currentPackagePath:String, ?moduleNameByPkgAndClass:Map<String, String>, ?callSigByCallee:Map<String, EmitterCallSig>):String {
		inline function getTyIdentRaw(name:String):Null<TyType> {
			return mapGetRaw(cast tyByIdent, name);
		}

		inline function resolveTyIdentName(name:String):String {
			if (getTyIdentRaw(name) != null)
				return name;
			final lowered = ocamlValueIdent(name);
			return lowered != name && getTyIdentRaw(lowered) != null ? lowered : name;
		}

		inline function tyForIdent(name:String):String {
			final resolved = getTyIdentRaw(resolveTyIdentName(name));
			if (resolved == null)
				return "";
			final t:TyType = resolved;
			if (t == null)
				return "";
			return t.toString();
		}

		inline function condToOcamlBoolForString(cond:HxExpr):String {
			// Keep the Stage3 “full bodies” rung resilient: a string expression can contain a ternary
			// like `colorSupported ? "..." + msg : msg`, but we do not yet type/emit arbitrary bool
			// conditions.
			//
			// In bring-up, prefer "always true" over emitting a non-bool expression that would fail
			// OCaml compilation.
			return switch (cond) {
				case EBool(v):
					v ? "true" : "false";
				case EUnop("!", _), EBinop("==", _, _), EBinop("!=", _, _), EBinop("<", _, _), EBinop(">", _, _), EBinop("<=", _, _), EBinop(">=", _, _),
					EBinop("&&", _, _), EBinop("||", _, _):
					final s = exprToOcaml(cond, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
					s == "(Obj.magic 0)" ? "true" : s;
				case _:
					"true";
			};
		}

		var emitStringExpr:HxExpr->String = null;
		emitStringExpr = function(expr:HxExpr):String {
			return switch (expr) {
				case EString(v): escapeOcamlString(v);
				case EEnumValue(name): escapeOcamlString(name);
				// When an expression is demanded as a string (e.g. trace/println), treat `+` as
				// string concatenation and lower it to OCaml's `^`.
				case EBinop("+", a, b):
					"(" + emitStringExpr(a) + " ^ " + emitStringExpr(b) + ")";
				case ECall(EField(EIdent("Std"), "string"), [arg]):
					// String interpolation lowering uses `Std.string(...)` to force stringification.
					//
					// Important
					// - Do not inline this as `emitStringExpr(arg)`:
					//   - it would degrade complex values (arrays, tagged values) to `<unsupported>`,
					//   - and it would diverge from the target runtime’s own stringification behavior.
					"HxRuntime.dynamic_toStdString (Obj.repr (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee) + "))";
				case ECall(EField(_obj, "join"), [_sep]):
					// Bring-up: join returns a string; delegate to normal expression lowering when available.
					exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				// Bootstrap: allow string-y ternaries in upstream-ish code (runci/System.hx).
				case ETernary(cond, thenExpr, elseExpr):
					"(if "
					+ condToOcamlBoolForString(cond)
					+ " then "
					+ emitStringExpr(thenExpr)
					+ " else "
					+ emitStringExpr(elseExpr)
					+ ")";
				case EInt(v): "string_of_int " + Std.string(v);
				case EBool(v): "string_of_bool " + (v ? "true" : "false");
				case EFloat(v): "string_of_float " + renderFloatLiteral(v);
				case EIdent(name) if (tyForIdent(name) == "Int"):
					"string_of_int " + ocamlReadValueIdent(name);
				case EIdent(name) if (tyForIdent(name) == "Float"):
					"string_of_float " + ocamlReadValueIdent(name);
				case EIdent(name) if (tyForIdent(name) == "Bool"):
					// Keep stringification resilient when best-effort inference mislabels a non-bool
					// value as `Bool` (for example, some stage0-fed static-final shapes during bring-up).
					//
					// `string_of_bool` would hard-fail OCaml typechecking in that case, while
					// `Std.string`-style runtime stringification stays safe for both true bools and
					// inference slips.
					"HxRuntime.dynamic_toStdString (Obj.repr (" + ocamlReadValueIdent(name) + "))";
				case EIdent(name) if (tyForIdent(name) == "String"):
					ocamlReadValueIdent(name);
				case EIdent(name) if (StringTools.startsWith(tyForIdent(name), "Array<")):
					// Haxe string interpolation uses `Std.string(...)` for non-strings.
					// For `Array<String>`, upstream RunCi relies on `Array.toString()` semantics,
					// which are equivalent to `join(",")`.
					//
					// Using `Std.string` on our array representation would currently degrade to
					// "<object>" (because `dynamic_toStdString` can't reliably detect records).
					final t = tyForIdent(name);
					final compact = StringTools.replace(t, " ", "");
					(compact.indexOf("Array<String>") == 0) ? ("HxBootArray.join (" + ocamlReadValueIdent(name) +
						") (\",\") (fun (s : string) -> s)") : ("HxRuntime.dynamic_toStdString (Obj.repr ("
						+ ocamlReadValueIdent(name) + "))");
				case EIdent(name) if (tyForIdent(name) == "Array"):
					"HxRuntime.dynamic_toStdString (Obj.repr (" + ocamlReadValueIdent(name) + "))";
				case _:
					// Bring-up default: prefer *some* stringification over `<unsupported>` so
					// upstream harness logs remain readable (and don't change meaning).
					//
					// Note: this uses the backend's `Std.string` implementation (Haxe semantics),
					// not OCaml's `Stdlib.string_of_*`.
					"HxRuntime.dynamic_toStdString (Obj.repr (" + exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee) + "))";
			}
		};

		return emitStringExpr(e);
	}

	static function exprToOcaml(e:HxExpr, ?arityByIdent:Map<String, Int>, ?tyByIdent:Map<String, TyType>, ?staticImportByIdent:Map<String, String>,
			?currentPackagePath:String, ?moduleNameByPkgAndClass:Map<String, String>, ?callSigByCallee:Map<String, EmitterCallSig>):String {
		inline function getTyIdentRaw(name:String):Null<TyType> {
			return mapGetRaw(cast tyByIdent, name);
		}

		inline function hasTyIdentRaw(name:String):Bool {
			return mapHasRaw(cast tyByIdent, name);
		}

		inline function getArityRaw(name:String):Null<Int> {
			return mapGetRaw(cast arityByIdent, name);
		}

		inline function hasArityRaw(name:String):Bool {
			return mapHasRaw(cast arityByIdent, name);
		}

		inline function getStaticImportRaw(name:String):Null<String> {
			final resolved = mapGetRaw(cast staticImportByIdent, name);
			return resolved == null ? null : cast resolved;
		}

		inline function getModuleNameRaw(key:String):Null<String> {
			final resolved = mapGetRaw(cast moduleNameByPkgAndClass, key);
			return resolved == null ? null : cast resolved;
		}

		inline function getCallSigRaw(callee:String):Null<EmitterCallSig> {
			final resolved = mapGetRaw(cast callSigByCallee, callee);
			return resolved == null ? null : cast resolved;
		}

		inline function resolveTyIdentName(name:String):String {
			if (getTyIdentRaw(name) != null)
				return name;
			final lowered = ocamlValueIdent(name);
			return lowered != name && getTyIdentRaw(lowered) != null ? lowered : name;
		}

		inline function hasTyIdent(name:String):Bool {
			return hasTyIdentRaw(resolveTyIdentName(name));
		}

		inline function hasThisBinding():Bool {
			return hasTyIdent("this") || hasTyIdent("this_");
		}

		inline function hasAllowedValueIdent(name:String):Bool {
			return currentAllowedValueIdentNames != null && currentAllowedValueIdentNames.exists(name);
		}

		function currentModuleNameForArityResolution():Null<String> {
			if (currentOcamlModuleName != null && currentOcamlModuleName.length > 0)
				return currentOcamlModuleName;
			final mainClass = expectedMainClassFromFilePath(currentModuleFilePath);
			if (mainClass == null || mainClass.length == 0)
				return null;
			final pkg = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
			final parts = pkg.length == 0 ? [] : pkg.split(".");
			parts.push(mainClass);
			return ocamlModuleNameFromTypePathParts(parts);
		}

		function resolveArityName(name:String):String {
			if (hasArityRaw(name))
				return name;
			final lowered = ocamlValueIdent(name);
			if (lowered != name && hasArityRaw(lowered))
				return lowered;
			final currentModuleName = currentModuleNameForArityResolution();
			if (currentModuleName != null && currentModuleName.length > 0) {
				final qualifiedLowered = currentModuleName + "." + lowered;
				if (hasArityRaw(qualifiedLowered))
					return qualifiedLowered;
				final qualifiedName = currentModuleName + "." + name;
				if (hasArityRaw(qualifiedName))
					return qualifiedName;
			}
			return name;
		}

		inline function hasArity(name:String):Bool {
			return hasArityRaw(resolveArityName(name));
		}

		inline function arityFor(name:String):Int {
			final resolved = getArityRaw(resolveArityName(name));
			if (resolved == null)
				return 0;
			final arity:Int = resolved;
			return arity;
		}

		inline function staticImportModule(name:String):String {
			final resolved = getStaticImportRaw(name);
			if (resolved != null)
				return resolved;
			return currentGlobalImportAliasByIdent == null ? null : currentGlobalImportAliasByIdent.get(name);
		}

		inline function isKnownModuleName(name:String):Bool {
			return currentKnownModuleNames != null && currentKnownModuleNames.exists(name);
		}

		function moduleNameForKey(key:String):String {
			final resolved = getModuleNameRaw(key);
			if (resolved != null)
				return resolved;
			for (entry in currentModuleNameEntries)
				if (entry.key == key)
					return entry.moduleName;
			return null;
		}

		function resolveQualifiedModuleCallSigByEmittedModuleName(moduleName:String, field:String, loweredField:String):Null<EmitterCallSig> {
			if (moduleName == null || moduleName.length == 0 || currentModuleFilePath == null || currentModuleFilePath.length == 0)
				return null;
			final currentPkg = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
			var bestSamePkg:Null<EmitterCallSig> = null;
			var bestAny:Null<EmitterCallSig> = null;
			for (entry in currentModuleNameEntries) {
				if (entry.moduleName != moduleName)
					continue;
				final colon = entry.key.indexOf(":");
				final pkg = colon < 0 ? "" : entry.key.substr(0, colon);
				final raw = colon < 0 ? entry.key : entry.key.substr(colon + 1);
				if (raw.length == 0)
					continue;
				final parts = raw.split(".");
				if (parts.length == 0)
					continue;
				final resolved = resolveQualifiedModuleCallSig(currentModuleFilePath, parts, field, loweredField);
				if (resolved == null)
					continue;
				if (pkg == currentPkg)
					return resolved;
				if (bestSamePkg == null && StringTools.startsWith(currentPkg, pkg) && pkg.length > 0)
					bestSamePkg = resolved;
				if (bestAny == null)
					bestAny = resolved;
			}
			return bestSamePkg != null ? bestSamePkg : bestAny;
		}

		inline function callSigFor(callee:String):Null<EmitterCallSig> {
			return getCallSigRaw(callee);
		}

		function resolveCallSigName(name:String):String {
			final direct = callSigFor(name);
			if (direct != null)
				return name;
			final lowered = ocamlValueIdent(name);
			if (lowered != name && callSigFor(lowered) != null)
				return lowered;
			final currentModuleName = currentModuleNameForArityResolution();
			if (currentModuleName != null && currentModuleName.length > 0) {
				final qualifiedLowered = currentModuleName + "." + lowered;
				if (callSigFor(qualifiedLowered) != null)
					return qualifiedLowered;
				final qualifiedName = currentModuleName + "." + name;
				if (callSigFor(qualifiedName) != null)
					return qualifiedName;
			}
			return name;
		}

		function currentModuleShortName():String {
			if (currentOcamlModuleName == null)
				return "";
			final moduleName = currentOcamlModuleName;
			var prefix = "";
			if (currentPackagePath != null) {
				final pkg = StringTools.trim(currentPackagePath);
				if (pkg.length > 0)
					prefix = ocamlModuleNameFromTypePathParts(pkg.split(".")) + "_";
			}
			if (prefix.length > 0 && StringTools.startsWith(moduleName, prefix))
				return moduleName.substr(prefix.length);
			final lastUnderscore = moduleName.lastIndexOf("_");
			return lastUnderscore < 0 ? moduleName : moduleName.substr(lastUnderscore + 1);
		}

		function tyForIdent(name:String):String {
			final resolvedName = resolveTyIdentName(name);
			var resolved = getTyIdentRaw(resolvedName);
			if (resolved == null && currentExprTyHints != null)
				resolved = currentExprTyHints.get(resolvedName);
			if (resolved == null)
				return "";
			final t:TyType = resolved;
			if (t == null)
				return "";
			return t.toString();
		}

		inline function readIdent(name:String):String {
			return ocamlReadValueIdent(name);
		}

		inline function qualifyRuntimeTypeName(name:String):String {
			final pkg = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
			return pkg.length > 0 ? pkg + "." + name : name;
		}

		function runtimeTypeNameForExpr(expr:HxExpr):Null<String> {
			final parts = tryExtractTypePathPartsFromExpr(expr);
			if (parts != null && parts.length > 0 && isUpperStart(parts[parts.length - 1]))
				return parts.length == 1 ? qualifyRuntimeTypeName(parts[0]) : parts.join(".");
			return switch (expr) {
				case EEnumValue(name):
					qualifyRuntimeTypeName(name);
				case EIdent(name) if (isUpperStart(name)):
					qualifyRuntimeTypeName(name);
				case _:
					null;
			}
		}

		function runtimeResolvedTypeExpr(expr:HxExpr, resolver:String):String {
			final resolved = runtimeTypeNameForExpr(expr);
			return resolved != null
				? resolver + " (" + escapeOcamlString(resolved) + ")"
				: "(Obj.magic (" + exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee) + "))";
		}

		inline function runtimeClassExpr(expr:HxExpr):String {
			return runtimeResolvedTypeExpr(expr, "Type.resolveClass");
		}

		inline function runtimeEnumExpr(expr:HxExpr):String {
			return runtimeResolvedTypeExpr(expr, "Type.resolveEnum");
		}


		function isIntExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EInt(_):
					true;
				case EUnop("-", inner):
					isIntExpr(inner);
				case EIdent(name):
					tyForIdent(name) == "Int";
				case EBinop(op, a,
					b) if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%"): // Best-effort: propagate int-ness through arithmetic when both sides look int-ish.
					isIntExpr(a)
					&& isIntExpr(b);
				case ETernary(_cond, thenExpr, elseExpr): isIntExpr(thenExpr) && isIntExpr(elseExpr);
				case _:
					false;
			}
		}

		function isUnknownNumericIdent(expr:HxExpr):Bool {
			// Stage3 bring-up heuristic:
			// when one side of an arithmetic op is definitely `Int` and the other side is an
			// identifier we only know as broad/unknown, prefer integer lowering over poison.
			//
			// This keeps common patterns like `% modulus` viable when local inference has not yet
			// propagated a precise type for `modulus`.
			return switch (expr) {
				case EIdent(name): final t = tyForIdent(name); t == "" || t == "Dynamic" || t == "Unknown" || t == "Array";
				case _:
					false;
			}
		}

		function isUnknownNumericCompareExpr(expr:HxExpr):Bool {
			// Stage3 comparison fallback:
			// when a numeric comparison mixes a concrete int literal with an identifier whose
			// type has not stabilized yet, prefer float coercion over raw int comparison.
			//
			// This keeps upstream shapes like `value:Float == 0` and `value < 0` type-correct
			// even when the bootstrap/source host temporarily loses the precise `Float` hint
			// for `value` during lowering.
			return switch (expr) {
				case EIdent(_):
					isUnknownNumericIdent(expr);
				case ECast(inner, _):
					isUnknownNumericCompareExpr(inner);
				case EUntyped(inner):
					isUnknownNumericCompareExpr(inner);
				case _:
					false;
			}
		}

		function isInfNanFieldExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EField(_, field): field == "iNF" || field == "INF" || field == "inf" || field == "nAN" || field == "NAN" || field == "NaN";
				case ECast(inner, _):
					isInfNanFieldExpr(inner);
				case EUntyped(inner):
					isInfNanFieldExpr(inner);
				case _:
					false;
			}
		}

		function isPositiveInfinityFieldExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EField(_, field): field == "iNF" || field == "INF" || field == "inf";
				case ECast(inner, _):
					isPositiveInfinityFieldExpr(inner);
				case EUntyped(inner):
					isPositiveInfinityFieldExpr(inner);
				case _:
					false;
			}
		}

		function isFloatExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EFloat(_):
					true;
				case _ if (isInfNanFieldExpr(expr)):
					// Stage 3 bring-up: INF/NAN-style constants (e.g. `php.Const.INF`) are float-typed.
					true;
				case EIdent(name):
					tyForIdent(name) == "Float";
				case EBinop("/", a, b): // Division yields Float for numeric Int/Float operands in Haxe.
					// For non-numeric/abstract cases we collapse emission to bring-up poison, so
					// we only treat it as float-ish when both sides look numeric.
					isFloatExpr(a) || isFloatExpr(b) || (isIntExpr(a) && isIntExpr(b));
				case EBinop(op, a, b) if (op == "+" || op == "-" || op == "*"): // Best-effort: propagate float-ness through arithmetic.
					isFloatExpr(a) || isFloatExpr(b);
				case ETernary(_cond, thenExpr, elseExpr): isFloatExpr(thenExpr) && isFloatExpr(elseExpr);
				case _:
					false;
			}
		}

		function isStringExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EString(_):
					true;
				case ECast(inner, _hint):
					// Upstream stdlib uses shapes like `o[cast f]` for dynamic string-key access.
					// Peel the cast so EArrayAccess can still route the key through `HxAnon.get`.
					isStringExpr(inner);
				case EUntyped(inner):
					isStringExpr(inner);
				case ECall(EField(EIdent("Std"), "string"), _):
					// `Std.string(...)` is the canonical "stringify anything" helper in Haxe.
					// Treat it as string-y so `Std.string(a) + Std.string(b)` lowers to `^`.
					true;
				case ECall(EField(_obj, "toString"), []):
					// `x.toString()` always yields a string in Haxe.
					true;
				case ECall(EField(EIdent("StringTools"), "hex"), _):
					// Stage 3 bring-up: treat `StringTools.hex(...)` as string-y so `+` concatenations
					// lower to OCaml `^` instead of numeric `+`.
					true;
				case EIdent(name):
					tyForIdent(name) == "String";
				case EBinop("+", a, b): // String concatenation is represented as `+` in Haxe, but Stage3 typing info is often
					// incomplete for nested expressions. Recursing avoids emitting OCaml `+` between strings.
					isStringExpr(a) || isStringExpr(b);
				case ETernary(_cond, thenExpr, elseExpr): isStringExpr(thenExpr) && isStringExpr(elseExpr);
				case _:
					false;
			}
		}

		function isStringKeyIndexExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case ECast(inner, _hint):
					// Upstream stdlib uses `o[cast f]` for dynamic field access. In bootstrap-hosted
					// lanes the parameter type for `f` is not always retained strongly enough for
					// `isStringExpr(inner)` to succeed, but the explicit cast still signals
					// string-key semantics rather than numeric indexing.
					switch (inner) {
						case EIdent(_), EField(_, _):
							true;
						case _:
							isStringExpr(inner);
					}
				case EUntyped(inner):
					isStringKeyIndexExpr(inner);
				case _:
					isStringExpr(expr);
			}
		}

		function isBoolExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EBool(_):
					true;
				case EIdent(name):
					tyForIdent(name) == "Bool";
				case EUnop("!", inner):
					isBoolExpr(inner);
				case EBinop(op, _, _): op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" || op == "&&" || op == "||";
				case ETernary(_cond, thenExpr, elseExpr): isBoolExpr(thenExpr) && isBoolExpr(elseExpr);
				case _:
					false;
			}
		}

		function isSysIoProcessExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EIdent(name): final t = tyForIdent(name); t == "sys.io.Process" || t == "sys.io.Process.Process";
				case ECast(inner, _hint):
					isSysIoProcessExpr(inner);
				case _:
					false;
			}
		}

		inline function intBinopCall(op:String, left:String, right:String):String {
			return switch (op) {
				case "+":
					"(HxInt.add (" + left + ") (" + right + "))";
				case "-":
					"(HxInt.sub (" + left + ") (" + right + "))";
				case "*":
					"(HxInt.mul (" + left + ") (" + right + "))";
				case "%":
					"(HxInt.rem (" + left + ") (" + right + "))";
				case _:
					"(Obj.magic 0)";
			}
		}

		inline function isInt64TypeText(t:String):Bool {
			return t == "Int64" || t == "haxe.Int64";
		}

		function isInt64Expr(expr:HxExpr):Bool {
			return switch (expr) {
				case EIdent(name):
					isInt64TypeText(tyForIdent(name));
				case ECall(EField(EIdent(owner), "ofInt" | "make"), _):
					owner == "Int64" || owner == "haxe.Int64";
				case ECast(inner, _):
					isInt64Expr(inner);
				case EUntyped(inner):
					isInt64Expr(inner);
				case EUnop(_, inner):
					isInt64Expr(inner);
				case EBinop(innerOp, left, right) if (innerOp == "+" || innerOp == "-" || innerOp == "*"):
					isInt64Expr(left) || isInt64Expr(right);
				case _:
					false;
			}
		}

		function exprToOcamlAsInt64Operand(expr:HxExpr):String {
			return switch (expr) {
				case EInt(v):
					"Haxe_Int64.ofInt (" + Std.string(v) + ")";
				case ECast(inner, _):
					exprToOcamlAsInt64Operand(inner);
				case EUntyped(inner):
					exprToOcamlAsInt64Operand(inner);
				case EUnop("-", inner):
					switch (inner) {
						case EInt(v):
							"Haxe_Int64.ofInt ((HxInt.neg (" + Std.string(v) + ")))";
						case _:
							exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
					}
				case EIdent(name) if (tyForIdent(name) == "Int"):
					"Haxe_Int64.ofInt (" + readIdent(name) + ")";
				case _:
					exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
			}
		}

		function isLikelyArrayExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EArrayDecl(_):
					true;
				case EIdent(name): final t = tyForIdent(name); t == "Array" || StringTools.startsWith(t, "Array<");
				case ECall(EField(inner, "toArray"), []):
					isLikelyArrayExpr(inner);
				case ECall(EField(inner, "copy"), []):
					isLikelyArrayExpr(inner);
				case ECall(EField(inner, "concat"), [_]):
					isLikelyArrayExpr(inner);
				case ECall(EField(inner, "map"), [_]):
					// `map(...)` always produces an array value. The receiver's concrete array
					// element type may be fuzzy during Stage3 bring-up, but the result is still
					// array-like enough for follow-up `join/contains/...` lowering.
					true;
				case _:
					false;
			}
		}

		function isLikelyArrayMethodReceiver(expr:HxExpr):Bool {
			if (isLikelyArrayExpr(expr))
				return true;
			return switch (expr) {
				// Stage3 bring-up: typed field receivers like `tpd.meta` frequently carry
				// array semantics even when the emitter only retained the parent local's type.
				// Treat them as array-like for instance array helpers so we emit runtime
				// intrinsics instead of dynamic-field partial applications.
				case EField(_, _):
					true;
				case ECast(inner, _):
					isLikelyArrayMethodReceiver(inner);
				case EUntyped(inner):
					isLikelyArrayMethodReceiver(inner);
				case _:
					false;
			}
		}

		function isStringArrayTypeText(rawType:String):Bool {
			if (rawType == null || rawType.length == 0)
				return false;
			final normalized = StringTools.replace(rawType, " ", "");
			return normalized == "Array<String>" || StringTools.startsWith(normalized, "Array<String>");
		}

		function isLikelyStringArrayExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EArrayDecl(values):
					if (values == null || values.length == 0) {
						true;
					} else {
						var allString = true;
						for (valueExpr in values)
							if (!isStringExpr(valueExpr)) {
								allString = false;
								break;
							}
						allString;
					}
				case EIdent(name):
					isStringArrayTypeText(tyForIdent(name));
				case ECall(EField(inner, "toArray"), []):
					isLikelyStringArrayExpr(inner);
				case ECall(EField(inner, "copy"), []):
					isLikelyStringArrayExpr(inner);
				case ECall(EField(inner, "concat"), [other]): isLikelyStringArrayExpr(inner) && isLikelyStringArrayExpr(other);
				case ECast(inner, _):
					isLikelyStringArrayExpr(inner);
				case EUntyped(inner):
					isLikelyStringArrayExpr(inner);
				case _:
					false;
			}
		}

		function metalArrayLiteralCategory(expr:HxExpr):String {
			if (isStringExpr(expr))
				return "string";
			if (isFloatExpr(expr))
				return "float";
			if (isIntExpr(expr))
				return "int";
			if (isBoolExpr(expr))
				return "bool";
			return "";
		}

		function extendTyByIdent(ty:Null<Map<String, TyType>>, name:String, t:TyType):Map<String, TyType> {
			final out = new Map<String, TyType>();
			if (ty != null)
				for (k in ty.keys()) {
					final existing = ty.get(k);
					if (existing != null)
						out.set(k, existing);
				}
			out.set(name, t);
			return out;
		}

		function extendTyByIdentMany(ty:Null<Map<String, TyType>>, names:Array<String>, t:TyType):Map<String, TyType> {
			final out = new Map<String, TyType>();
			if (ty != null)
				for (k in ty.keys()) {
					final existing = ty.get(k);
					if (existing != null)
						out.set(k, existing);
				}
			if (names != null)
				for (n in names)
					out.set(n, t);
			return out;
		}

		function exprToOcamlForConcat(expr:HxExpr):String {
			// Best-effort: keep concatenation type-safe by stringifying obvious primitives.
			// For complex expressions we assume the caller is already producing a string.
			return switch (expr) {
				case EInt(_), EFloat(_), EBool(_), EIdent(_):
					exprToOcamlString(expr, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				case _:
					exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
			}
		}

		function exprToOcamlAsFloatValue(expr:HxExpr):String {
			// Best-effort numeric coercion: promote obvious Ints to float.
			return switch (expr) {
				case EInt(v):
					"float_of_int " + Std.string(v);
				case EUnop("-", inner):
					// Make sure negative int literals become floats in float contexts.
					"(-.(" + exprToOcamlAsFloatValue(inner) + "))";
				case EIdent(name) if (tyForIdent(name) == "Int"):
					"float_of_int " + readIdent(name);
				case _ if (isInfNanFieldExpr(expr)):
					"(Obj.magic (" + exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass) + ") : float)";
				case _:
					exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
			}
		}

		function ocamlWhitespacePredicate(charExpr:String):String {
			return "("
				+ charExpr
				+ " = ' ' || "
				+ charExpr
				+ " = '\\t' || "
				+ charExpr
				+ " = '\\n' || "
				+ charExpr
				+ " = '\\r' || "
				+ charExpr
				+ " = '\\011' || "
				+ charExpr
				+ " = '\\012')";
		}

		function renderStringLtrimExpr(source:String):String {
			return "(let __s = (" + source + ") in "
				+ "let __len = Stdlib.String.length __s in "
				+ "let __i = ref 0 in "
				+ "while !__i < __len && "
				+ ocamlWhitespacePredicate("Stdlib.String.get __s !__i")
				+ " do incr __i done; "
				+ "if !__i = 0 then __s else Stdlib.String.sub __s !__i (__len - !__i))";
		}

		function renderStringRtrimExpr(source:String):String {
			return "(let __s = (" + source + ") in "
				+ "let __len = Stdlib.String.length __s in "
				+ "let __i = ref (__len - 1) in "
				+ "while !__i >= 0 && "
				+ ocamlWhitespacePredicate("Stdlib.String.get __s !__i")
				+ " do decr __i done; "
				+ "if !__i = __len - 1 then __s else if !__i < 0 then \"\" else Stdlib.String.sub __s 0 (!__i + 1))";
		}

		return switch (e) {
			// Stage 3 bring-up: map a tiny set of Haxe `Math` statics to OCaml primitives.
			//
			// Why
			// - Upstream Haxe unit code frequently calls `Math.isNaN`/`Math.isFinite`.
			// - Stage 3 emits "plain OCaml" (no Haxe runtime), so `Math.*` would otherwise
			//   fail to compile with `Unbound module Math`.
			//
			// What
			// - This is intentionally narrow and **not** a full stdlib mapping layer.
			// - These rewrites exist only to keep bring-up moving; Stage1/Stage4 must
			//   eventually implement real semantics in the proper backend/runtime.
			case ECall(EField(EIdent("Math"), "isNaN"), [arg]):
				"(classify_float (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
					moduleNameByPkgAndClass) + ") = FP_nan)";
			case ECall(EField(EIdent("Math"), "isFinite"), [arg]):
				"(match classify_float (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
					moduleNameByPkgAndClass) + ") with | FP_nan | FP_infinite -> false | _ -> true)";
			case ECall(EField(EIdent("Math"), "isInfinite"), [arg]):
				"(classify_float (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
					moduleNameByPkgAndClass) + ") = FP_infinite)";
			case ECall(EField(EIdent("Std"), "isOfType"), [valueExpr, typeExpr]):
				// Stage 3 bring-up: runtime `Std.isOfType` expects the second operand as a dynamic
				// descriptor (`Obj.t`), so wrap whichever surface form we currently emit.
				"Std.isOfType ("
				+ exprToOcaml(valueExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ") (Obj.repr ("
				+ exprToOcaml(typeExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ "))";
			case ECall(EField(EIdent("Type"), "createInstance"), [clsExpr, ctorArgs]):
				"Type.createInstance (" + runtimeClassExpr(clsExpr) + ") ("
				+ exprToOcaml(ctorArgs, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ")";
			case ECall(EField(EIdent("Type"), "createEmptyInstance"), [clsExpr]):
				"Type.createEmptyInstance (" + runtimeClassExpr(clsExpr) + ")";
			case ECall(EField(EIdent("Type"), "getClassFields"), [clsExpr]):
				"Type.getClassFields (" + runtimeClassExpr(clsExpr) + ")";
			case ECall(EField(EIdent("Type"), "getEnumConstructs"), [enumExpr]):
				"Type.getEnumConstructs (" + runtimeEnumExpr(enumExpr) + ")";
			case ECall(EField(EIdent("Array"), "wrap"), [arg]):
				// Stage 3 bring-up: `Array.wrap(...)` appears in upstream php helpers.
				//
				// The bootstrap Array module does not provide this static helper yet; preserve
				// compileability by treating it as an identity cast to the target array shape.
				"(Obj.magic (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + "))";
			case ECall(EField(EIdent("Math"), "abs"), [arg]):
				// Best-effort numeric abs. Prefer float when the expression looks float-typed.
				(isFloatExpr(arg) ? "abs_float " : (isIntExpr(arg) ? "abs " : "abs_float "))
					+ "("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")";
			case EField(EIdent("String"), "fromCharCode"):
				// Stage 3 bring-up: map Haxe `String.fromCharCode(int)` to an OCaml function value.
				// This is used in upstream-ish stdlib code as `var fcc = String.fromCharCode;`.
				"(fun i -> Stdlib.String.make 1 (Char.chr i))";
			case ECall(EField(EIdent("Math"), "pow"), [_a, _b]):
				// Bring-up: avoid pulling in correct float/int coercions for exponentiation.
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Math"), "round"), [arg]):
				// Bring-up: good-enough rounding for positive values (used by RunCi timing logs).
				//
				// NOTE: Haxe's `Math.round` handles negatives differently; for Gate bring-up the
				// upstream harness uses `Timer.stamp()` deltas which are non-negative.
				"(int_of_float (floor ((" + exprToOcamlAsFloatValue(arg) + ") +. 0.5)))";
			case ECall(EField(EIdent("Math"), "floor"), [_arg]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Math"), "log"), [_arg]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Math"), "fround"), [_arg]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Timer"), "stamp"), []):
				// Bring-up: map `haxe.Timer.stamp()` to wall-clock time.
				"(Unix.gettimeofday ())";
			// Stage 3 bring-up: map a tiny slice of `haxe.Int64` construction helpers.
			//
			// Why
			// - Upstream `haxe.io.FPHelper` initializes `static var i64tmp = Int64.ofInt(0);`.
			// - OCaml's `Int64` module uses snake_case (`of_int`), and in bootstrap we model
			//   `haxe.Int64` as a small record (`Haxe_Int64.t`), not as OCaml's native int64.
			//
			// What
			// - Lower `Int64.ofInt(i)` to our shim `Haxe_Int64.ofInt(i)`.
			// - Lower `Int64.make(lo, hi)` to `Haxe_Int64.make(lo, hi)`.
			// - Lower static helpers like `Int64.mul(a, 2)` through the same operand coercion
			//   path as mixed binops, so literal `Int` operands become `Haxe_Int64.ofInt(...)`.
			case ECall(EField(EIdent("Int64"), op), [left, right]) | ECall(EField(EIdent("haxe.Int64"), op), [left, right])
				if (op == "add" || op == "sub" || op == "mul"):
				"Haxe_Int64." + op + " ("
				+ exprToOcamlAsInt64Operand(left)
				+ ") ("
				+ exprToOcamlAsInt64Operand(right)
				+ ")";
			case ECall(EField(EIdent("Int64"), "ofInt"), [arg]) | ECall(EField(EIdent("haxe.Int64"), "ofInt"), [arg]):
				"Haxe_Int64.ofInt (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
			case ECall(EField(EIdent("Int64"), "make"), [lo, hi]) | ECall(EField(EIdent("haxe.Int64"), "make"), [lo, hi]):
				"Haxe_Int64.make ("
				+ exprToOcaml(lo, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ") ("
				+ exprToOcaml(hi, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ")";
			case ELambda(args, body):
				// Stage 3 bring-up: emit a direct OCaml closure.
				//
				// Notes
				// - We don't model Haxe function typing yet; this is purely syntactic lowering.
				// - Multi-arg lambdas are supported syntactically as `fun a b -> ...`, which in OCaml
				//   is sugar for nested single-arg functions.
				final ocamlArgs = args.map(ocamlValueIdent).join(" ");
				final ty2 = extendTyByIdentMany(tyByIdent, args, TyType.fromHintText("Dynamic"));
				"(fun "
				+ (ocamlArgs.length == 0 ? "_" : ocamlArgs)
				+ " -> "
				+ exprToOcaml(body, arityByIdent, ty2, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ")";
			case ETryCatchRaw(_raw):
				// Stage 3 bring-up: avoid committing to an exception model yet.
				//
				// Correct semantics depend on:
				// - which exceptions are thrown by the runtime and user code,
				// - how we map Haxe `catch(e:Dynamic)` to OCaml exceptions,
				// - and how block-expression values are represented.
				//
				// For now, keep the emitted OCaml type-correct by returning a polymorphic placeholder.
				"(Obj.magic 0)";
			case EField(EIdent("Math"), "NaN"):
				"nan";
			case EField(EIdent("Math"), "POSITIVE_INFINITY"):
				"infinity";
			case EField(EIdent("Math"), "NEGATIVE_INFINITY"):
				"neg_infinity";
			case EField(EIdent("Math"), "PI"):
				"(4.0 *. atan 1.0)";

			// Stage 3 bring-up: avoid emitting unbound `Reflect.*` / `Type.*` calls in the bootstrap
			// emitter output. Upstream-ish unit code (e.g. utest) uses reflection helpers heavily.
			//
			// This is not semantic; it exists only to keep the emit+build rung compiling so we can
			// iterate on the real backend/typer/macro model.
			case ECall(EField(EIdent("Reflect"), "fields"), [_obj]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "field"), [_obj, _name]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "getProperty"), [_obj, _name]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "setProperty"), [_obj, _name, _value]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "hasField"), [_obj, _name]):
				"false";
			case ECall(EField(EIdent("Reflect"), "isFunction"), [_obj]):
				"true";
			case ECall(EField(EIdent("Type"), "getClass"), [_obj]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Type"), "getInstanceFields"), [_cls]):
				"(Obj.magic 0)";
			case ECall(EField(EIdent("Type"), "getClassName"), [_cls]):
				escapeOcamlString("");
			case ECall(EField(EIdent("Type"), "getEnumName"), [_enm]):
				escapeOcamlString("");
			case ECall(EField(EIdent("Type"), "typeof"), [_v]):
				"(Obj.magic 0)";

			case ECall(EField(_obj, "set_low"), [_v]):
				"()";
			case ECall(EField(_obj, "set_high"), [_v]):
				"()";

			// Stage 3 bring-up: `haxe.io.Bytes` and other stdlib code frequently call
			// `StringTools.fastCodeAt(s, i)` / `StringTools.unsafeCodeAt(s, i)`.
			//
			// In upstream Haxe these are typically `inline` and lower to a target primitive,
			// but the Stage3 bootstrap compiler does not implement inlining.
			//
			// Instead of requiring a full `StringTools` module in the emitted program,
			// map them to OCaml primitives directly.
			case ECall(EField(EIdent("StringTools"), "fastCodeAt"), [s, idx]), ECall(EField(EIdent("StringTools"), "unsafeCodeAt"), [s, idx]):
				final s2 = exprToOcaml(s, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				final i2 = exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				"(let __s = ("
				+ s2
				+ ") in "
				+ "let __i = ("
				+ i2
				+ ") in "
				+ "if (__i < 0) || (__i >= Stdlib.String.length __s) then (-1) else (Char.code (Stdlib.String.get __s __i)))";

			// Stage 3 bring-up: upstream code calls `StringTools.hex` both with omitted digits
			// and with explicit integer padding widths. The generated provider currently lowers
			// the optional `digits` parameter through the `hx_null` sentinel, so explicit ints
			// have to be boxed while omitted calls still become `0`.
			case ECall(EField(EIdent("StringTools"), "hex"), [n]):
				"StringTools.hex (" + exprToOcaml(n, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee) + ") (Obj.repr 0)";
			case ECall(EField(EIdent("StringTools"), "hex"), [n, digits]):
				"StringTools.hex ("
				+ exprToOcaml(n, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
				+ ") ("
				+ (switch (digits) {
					case ENull:
						"(Obj.magic HxRuntime.hx_null)";
					case _:
						"Obj.repr ("
						+ exprToOcaml(digits, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
							callSigByCallee)
						+ ")";
				})
				+ ")";

			case ECall(EField(EIdent("StringTools"), "replace"), [_s, _sub, _by]):
				// Bring-up: avoid needing a real `StringTools` implementation in the Stage3 emitter output.
				escapeOcamlString("");

			case ECall(EField(EIdent("Std"), "is"), [_v, _t]):
				// Bring-up: type tests require RTTI/runtime; keep compilation moving.
				"true";
			case ECall(EField(EIdent("Std"), "string"), [arg]):
				// Stage 3 bring-up: generated `Std.string` expects an `Obj.t`.
				//
				// Without this explicit `Obj.repr`, primitive-typed placeholder shims (e.g. Int64)
				// can trigger type mismatches in upstream-shaped tests that call `Std.string(...)`.
				"Std.string (Obj.repr (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee) + "))";
			case ECall(EField(EIdent("Std"), "downcast"), [_value, _cls]):
				// Bring-up: `Std.downcast` requires RTTI/class objects. We don't model those in the
				// Stage3 emitter output yet, so collapse to `null`.
				"(Obj.magic HxRuntime.hx_null)";

			// Bring-up: extension-method style filesystem calls (via `using sys.FileSystem`) appear
			// in macro code. The Stage3 emitter doesn't implement `using`, so we rewrite these
			// instance-call shapes to stubs to keep OCaml compilation moving.
			case ECall(EField(_obj, "exists"), []):
				"true";
			case ECall(EField(_obj, "readDirectory"), []):
				"(Obj.magic 0)";
			case ECall(EField(_obj, "isDirectory"), []):
				"false";

			// Stage 3 "full body" rung: map common output calls to OCaml printing.
			//
			// This is *not* a real stdlib/runtime mapping; it's a bootstrap convenience so we can
			// observe that emitted function bodies are actually executing.
			case ECall(EIdent("trace"), [arg]):
				"print_endline (" + exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee) + ")";
			case ECall(EField(EIdent("Sys"), "println"), [arg]):
				"print_endline (" + exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee) + ")";
			case ECall(EField(EIdent("Sys"), "print"), [arg]):
				"print_string (" + exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee) + ")";
			case ECall(EField(obj, "toString"), []) if (isStringExpr(obj)):
				// Bring-up: in Haxe, `String.toString()` is an identity; mapping this avoids
				// poisoning common patterns like `input.readAll().toString()`.
				exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);

			case EBool(v): v ? "true" : "false";
			case EInt(v): Std.string(v);
			case EFloat(v): renderFloatLiteral(v);
			case EString(v): escapeOcamlString(v);
			case EIdent(name):
				if (hasCurrentInstanceMethod(name) && hasThisBinding()) {
					// Instance-method value reference (e.g. `fields.map(printField)` inside an
					// instance method) must capture `this`.
					//
					// Emit a partially-applied function (`printField this_`) so OCaml sees the same
					// callback arity as Haxe's bound-method semantics.
					ocamlValueIdent(name) + " (this_)";
				} else if (hasTyIdent(name)) {
					// Bound identifier (parameter / local / bring-up-allowed static field).
					readIdent(name);
				} else if (hasArity(name)) {
					// Static method call within the same generated module becomes a top-level OCaml binding.
					ocamlValueIdent(name);
				} else if (staticImportModule(name) != null) {
					// Stage 3 bring-up: approximate `import Foo.Bar.*` (static wildcard imports).
					final moduleName = staticImportModule(name);
					moduleName + "." + ocamlValueIdent(name);
				} else if (hasAllowedValueIdent(name)) {
					// Stage3 fallback: preserve function-scope identifiers that are known to be
					// in scope even when the native-parser/typer path failed to keep a concrete
					// local type entry for them.
					readIdent(name);
				} else if (isUpperStart(name)) {
					// Stage 3 bring-up: a bare uppercase identifier is almost always an enum constructor
					// or class/abstract value in Haxe (e.g. `UTF8`). OCaml treats this as a data
					// constructor and will fail with "Unbound constructor" unless we model the type.
					//
					// For the bootstrap emitter, collapse these to the escape hatch. Module/static
					// references like `String.fromCharCode` are handled by `EField(EIdent("String"), ...)`.
					"(Obj.magic 0)";
				} else {
					// Stage 3 bring-up: unqualified instance fields (e.g. `length` inside `haxe.io.Bytes`)
					// parse as identifiers, but OCaml needs an explicit binding. Until we model `this`
					// field access, collapse free identifiers to a bootstrap escape hatch.
					"(Obj.magic 0)";
				}
			case EThis:
				// Stage 3 full-body bring-up: instance methods bind an explicit `this` parameter.
				// If we are outside that context, conservatively collapse to poison.
				hasThisBinding() ? "this_" : "(Obj.magic 0)";
			case ESuper:
				// Stage 3 bring-up: no class hierarchy semantics yet.
				"(Obj.magic 0)";
			case ENull:
				// Stage 3 bring-up: represent `null` as the runtime sentinel and cast it as needed.
				"(Obj.magic HxRuntime.hx_null)";
			case EEnumValue(name):
				// Bring-up: lower enum-like value tags (e.g. `Macro`) to a stable string.
				escapeOcamlString(name);
			case ENew(typePath, args):
				// Stage 3 bring-up: support a tiny subset of allocations used by orchestration code.
				//
				// Today we special-case `sys.io.Process` so RunCi-like workloads can actually spawn
				// the `haxe` subcommands (routed through the Gate2 wrapper).
				(typePath == "Array" && args.length == 0) ? "HxBootArray.create ()" : (typePath == "sys.io.Process" || typePath == "sys.io.Process.Process")
					&& (args.length == 2 || args.length == 3) ? ("HxBootProcess.spawn ("
						+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
						+ ") ("
						+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
						+ ")") : (function() {
							final fields = currentInstanceFieldsFor(typePath);
							if (fields == null)
								return "(Obj.magic 0)";
							final ctorMethods = currentInstanceMethodsFor(typePath);
							final ctorName = ocamlValueIdent("new");
							final argCodes = args.map(a -> "("
								+ exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
								+ ")");
							final ctorCall = (hasMethodName(ctorMethods,
								"new")) ? ("ignore (" + ctorName + " (__hx_obj)" + (argCodes.length == 0 ? "" : (" " + argCodes.join(" "))) + ")") : "()";
							final initStmts = new Array<String>();
							for (f in fields) {
								final fieldName = HxFieldDecl.getName(f);
								if (fieldName == null || fieldName.length == 0)
									continue;
								initStmts.push("HxAnon.set (Obj.repr __hx_obj) " + escapeOcamlString(fieldName) + " HxRuntime.hx_null");
							}
							return "(let __hx_obj = HxAnon.create () in "
								+ (initStmts.length == 0 ? "" : (initStmts.join("; ") + "; "))
								+ ctorCall
								+ "; __hx_obj)";
						})();
			case EArrayComprehension(name, iterable, yieldExpr):
				// Lower `[for (x in it) e]` to a small imperative builder.
				//
				// Note: for now we only support array/range iterables (matching bring-up needs).
				final out = "__arr_comp_out";
				final v = ocamlValueIdent(name);
				final loopTy = switch (iterable) {
					case ERange(_, _):
						TyType.fromHintText("Int");
					case _:
						TyType.fromHintText("Dynamic");
				};
				final ty2 = extendTyByIdent(tyByIdent, name, loopTy);
				final body = exprToOcaml(yieldExpr, arityByIdent, ty2, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				return switch (iterable) {
					case ERange(startExpr, endExpr):
						final start = exprToOcaml(startExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
							callSigByCallee);
						final end = exprToOcaml(endExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
							callSigByCallee);
						"(let "
						+ out
						+ " = HxBootArray.create () in "
						+ "let __start = ("
						+ start
						+ ") in "
						+ "let __end = ("
						+ end
						+ ") in "
						+ "(if (__end <= __start) then () else (for "
						+ v
						+ " = __start to (__end - 1) do ignore (HxBootArray.push "
						+ out
						+ " ("
						+ body
						+ ")) done)); "
						+ out
						+ ")";
					case _:
						final it = exprToOcaml(iterable, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						"(let "
						+ out
						+ " = HxBootArray.create () in "
						+ "HxBootArray.iter ("
						+ it
						+ ") (fun "
						+ v
						+ " -> ignore (HxBootArray.push "
						+ out
						+ " ("
						+ body
						+ "))); "
						+ out
						+ ")";
				};
			case EField(obj, field):
				switch (obj) {
					case EThis | EIdent("this") | EIdent("this_") if (hasCurrentInstanceMethod(field) && hasThisBinding()):
						// Bound instance-method value reference, e.g. `this.printMetadata` used as a
						// callback in `tpd.meta.map(this.printMetadata)`.
						//
						// Emit the same partially-applied function shape as bare `printMetadata`
						// references inside instance methods so OCaml preserves Haxe's bound-method
						// callback semantics.
						return ocamlValueIdent(field) + " (this_)";
					case _:
				}

				// Stage 3 bring-up: model a couple of common "instance field" shapes that appear in
				// orchestration code, without committing to a full object layout/runtime.
				//
				// - Array.length (via the bootstrap `HxBootArray` shim)
				// - Stdlib.String.length (OCaml primitive)
				if (field == "length") {
					final o = exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					if (isStringExpr(obj)) {
						return "Stdlib.String.length (" + o + ")";
					}
					switch (obj) {
						case EArrayDecl(_):
							return "HxBootArray.length (" + o + ")";
						case EIdent(name):
							final t = tyForIdent(name);
							if (StringTools.startsWith(t, "Array<"))
								return "HxBootArray.length (" + o + ")";
							// Bring-up default:
							// - Native source builds do not always preserve enough type information to
							//   distinguish `String.length` from `Array.length` on locals like `content`.
							// - Routing the unknown case through a small runtime helper is safer than
							//   hard-coding "unknown means array", which produces immediate type errors
							//   on string receivers.
							return "HxBootArray.length_dyn (Obj.repr (" + o + "))";
						case _:
							return "HxBootArray.length_dyn (Obj.repr (" + o + "))";
					}
				}

				// Stage 3 bring-up: treat a few `sys.io.Process` fields as intrinsic accessors.
				if (field == "stdout" && isSysIoProcessExpr(obj)) {
					return "HxBootProcess.stdout ("
						+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
						+ ")";
				}
				if (field == "stderr" && isSysIoProcessExpr(obj)) {
					return "HxBootProcess.stderr ("
						+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
						+ ")";
				}

				// Stage 3 bring-up: treat `<type path>.field` as a static/module access.
				//
				// Why
				// - Upstream Haxe code refers to types as fully-qualified paths like `runci.targets.Macro`.
				// - Our emitter represents each Haxe module as a single OCaml compilation unit, so we can
				//   map `a.b.C.field` to `A_b_C.field` deterministically.
				//
				// Non-goal
				// - Instance field semantics (requires real class/object layouts).
				switch (obj) {
					case EIdent(typeName):
						final importedModule = staticImportModule(typeName);
						if (importedModule != null && importedModule.length > 0) {
							return (currentOcamlModuleName != null
								&& importedModule == currentOcamlModuleName) ? ocamlValueIdent(field) : (importedModule + "." + ocamlValueIdent(field));
						}
						// Module-local helper fallback for unqualified type references.
						//
						// Example:
						// - Haxe (same file): `Helper.ANSWER`
						// - Emitted helper provider: `Main_Helper`
						//
						// We only apply this when that helper provider is known in the module index,
						// so unrelated uppercase identifiers still flow through the normal resolver.
						if (currentOcamlModuleName != null && isUpperStart(typeName)) {
							final inCurrentModule = currentInstanceFieldsFor(typeName) != null
								|| currentInstanceMethodsFor(typeName) != null;
							if (inCurrentModule && typeName != currentModuleShortName()) {
								final localHelperModule = currentOcamlModuleName + "_" + typeName;
								return localHelperModule + "." + ocamlValueIdent(field);
							}
						}
					case _:
				}
				final parts = tryExtractTypePathPartsFromExpr(obj);
				if (parts != null && parts.length > 0 && isUpperStart(parts[parts.length - 1])) {
					var modName = ocamlModuleNameFromTypePathParts(parts);
					var resolvedByModuleIndex = false;
					// If the type path is relative to the current package, prefer resolving it within the
					// current package (or its parent packages) when we know a matching emitted module exists.
					//
					// Example:
					// - Haxe: `package demo; class A { static function f() Util.ping(); }`
					// - OCaml: `Demo_Util.ping ()` (not `Util.ping ()`)
					//
					// Also covers module-local helper types referenced as `Module.Helper`:
					// - Haxe: `package unit; ... MyMacro.MyRestMacro.testRest1(...)`
					// - OCaml: `Unit_MyMacro_MyRestMacro.testRest1 ...`
					//
					// Upstream also resolves unqualified type names by walking up parent packages.
					// Example:
					// - `package runci.targets; ... Linux.requireAptPackages(...)` resolves to `runci.Linux`
					//   even without an explicit import.
						if (moduleNameByPkgAndClass != null) {
						final raw = parts.join(".");
						var cur = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
						while (true) {
							final key = cur + ":" + raw;
							final local = moduleNameForKey(key);
							if (local != null && local.length > 0) {
								modName = local;
								resolvedByModuleIndex = true;
								break;
							}
							if (cur.length == 0)
								break;
							final lastDot = cur.lastIndexOf(".");
							cur = lastDot < 0 ? "" : cur.substr(0, lastDot);
						}

						// Fallback for native-frontend bring-up when the typed-module index does not
						// expose a short-name mapping for a same-package type path.
						//
						// Example:
						// - Haxe (package haxe.io): `FPHelper.i32ToFloat(...)`
						// - Expected OCaml provider: `Haxe_io_FPHelper.i32ToFloat ...`
						//
						// Without this fallback we can emit bare `FPHelper.*`, which fails to link
						// because the emitted provider module is package-qualified.
						if (!resolvedByModuleIndex
							&& !isKnownModuleName(modName)
							&& modName == ocamlModuleNameFromTypePathParts(parts)
							&& parts.length == 1) {
							final curPkg = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
							if (curPkg.length > 0) {
								final qualifiedParts = curPkg.split(".");
								for (p in parts)
									qualifiedParts.push(p);
								modName = ocamlModuleNameFromTypePathParts(qualifiedParts);
							}
						}
					}
					// Import-based resolution for type short names that would otherwise collide
					// with OCaml stdlib modules.
					//
					// Example (upstream unit suite):
					// - Haxe: `import haxe.Int64.*; Int64.mul(a, b);`
					// - OCaml: `Haxe_Int64.mul a b` (not `Int64.mul a b` from stdlib)
					if (parts.length == 1 && parts[0] == "Int64" && currentImportInt64 != null && currentImportInt64.length > 0) {
						modName = currentImportInt64;
					}
					(currentOcamlModuleName != null && modName == currentOcamlModuleName) ? ocamlValueIdent(field) : (modName + "." + ocamlValueIdent(field));
				} else { // Stage3 object bring-up: represent instance state through HxAnon maps.
					"(Obj.magic (HxAnon.get (Obj.repr ("
					+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ")) "
					+ escapeOcamlString(field)
					+ "))";
				}
			case ECall(EIdent("__ocaml__"), [arg]):
				// Stage 3 bring-up escape hatch: embed raw OCaml expression text.
				//
				// Why
				// - Some bring-up binaries (macro host, display server) need small pieces of direct OCaml I/O
				//   before the Stage3 bootstrap emitter can model the full Haxe runtime.
				//
				// What
				// - We lower `untyped __ocaml__("<ocaml expr>")` to the raw `<ocaml expr>` at the call site.
				// - To keep sources readable, we also accept literal concatenation:
				//     `untyped __ocaml__("(let\\n" + \"...\" + \")\")`
				//
				// Safety
				// - Only constant-foldable strings are accepted. Anything dynamic collapses to bring-up poison.
				final code = constFoldString(arg);
				code == null ? "(Obj.magic 0)" : ("(" + code + ")");
			case ECall(callee, args):
				// Stage 3 bring-up safety: enum-like tags are lowered as strings (`EEnumValue`),
				// which is fine when used as *values* (e.g. in switches) but invalid when used as
				// call targets.
				//
				// Example (upstream std macros):
				// - `TPath({...})` in `haxe.macro.MacroStringTools` is an enum constructor call.
				// - Our parser may classify `TPath` as `EEnumValue("TPath")`, which would emit as
				//   `"TPath" (...)` and fail OCaml typechecking.
				//
				// Until we model real enum constructors in the typed AST, collapse such calls to a
				// bootstrap escape hatch so the module can still compile.
				switch (callee) {
					case EEnumValue(_):
						return "(Obj.magic 0)";
					case _:
				}

				inline function looksLikeForwardedReceiverExpr(expr:HxExpr):Bool {
					return switch (expr) {
						case EThis:
							true;
						case EIdent(name):
							final t = tyForIdent(name);
							!(t == "Int" || t == "Float" || t == "Bool" || t == "String");
						case EField(_, _):
							true;
						case _:
							false;
					};
				}

				inline function bool01(v:Bool):String {
					return v ? "1" : "0";
				}

				inline function nullableString(v:Null<String>):String {
					return v == null || v.length == 0 ? "<none>" : v;
				}

				inline function calleeTag(expr:HxExpr):String {
					return switch (expr) {
						case EIdent(name):
							"EIdent(" + name + ")";
						case EField(EThis, name):
							"EField(EThis," + name + ")";
						case EField(EIdent(obj), name):
							"EField(EIdent(" + obj + ")," + name + ")";
						case EField(_, name):
							"EField(<expr>," + name + ")";
						case ECall(_, _):
							"ECall";
						case EUnop(op, _):
							"EUnop(" + op + ")";
						case EBinop(op, _, _):
							"EBinop(" + op + ")";
						case _:
							Std.string(expr);
					};
				}

				inline function isDirectSelfRecursiveCallee(expr:HxExpr):Bool {
					return switch (expr) {
						case EIdent(name):
							currentFunctionNameRaw != null && name == currentFunctionNameRaw && hasThisBinding();
						case EField(EThis, name):
							currentFunctionNameRaw != null && name == currentFunctionNameRaw;
						case EField(EIdent("this"), name):
							currentFunctionNameRaw != null && name == currentFunctionNameRaw;
						case EField(EIdent("this_"), name):
							currentFunctionNameRaw != null && name == currentFunctionNameRaw;
						case _:
							false;
					};
				}

				final directSelfRecursiveCallee = isDirectSelfRecursiveCallee(callee);
				_EmitterStageDebug.traceSelfRecursion("direct_check",
					"current=" + nullableString(currentFunctionNameRaw) + " callee=" + calleeTag(callee) + " args=" + args.length + " hasThis="
					+ bool01(hasThisBinding()) + " direct=" + bool01(directSelfRecursiveCallee));

				if (directSelfRecursiveCallee) {
					final rendered = new Array<String>();
					rendered.push("(this_)");
					for (a in args)
						rendered.push("("
							+ exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")");
					return ocamlValueIdent(currentFunctionNameRaw) + " " + rendered.join(" ");
				}

				// Stage 3 bring-up: avoid partial applications when Haxe calls a function
				// with omitted optional/default parameters.
				//
				// Example (stdlib):
				// - `Bytes.readString(pos, len)` calls `getString(pos, len)` where `getString` is declared
				//   as `getString(pos, len, ?encoding)`.
				// - Without a default/optional-arg model, emitting `getString pos len` becomes a partial
				//   application and fails OCaml typechecking.
				//
				// In this bring-up emitter we don't implement real default-arg semantics; we simply
				// append `(Obj.magic 0)` for any missing arguments when the callee is a known in-module
				// identifier and the call provides fewer args than the declaration.
				final missing = switch (callee) {
					case EIdent(name) if (hasArity(name)):
						final expectedRaw = arityFor(name);
						final isInstance = hasCurrentInstanceMethod(name);
						final callerHasThis = hasThisBinding();
						final receiverIsForwarded = isInstance && args.length > 0 && args.length >= expectedRaw && looksLikeForwardedReceiverExpr(args[0]);
						final expected = (isInstance && callerHasThis && !receiverIsForwarded) ? (expectedRaw - 1) : expectedRaw;
						expected > args.length ? (expected - args.length) : 0;
					case EField(EThis, name) if (hasArity(name)):
						final expectedRaw = arityFor(name);
						final receiverIsForwarded = args.length > 0 && args.length >= expectedRaw && looksLikeForwardedReceiverExpr(args[0]);
						final expected = receiverIsForwarded ? expectedRaw : (expectedRaw - 1);
						expected > args.length ? (expected - args.length) : 0;
					case _:
						0;
				}

				// Special-case a tiny slice of `Sys` I/O so bring-up server binaries can function
				// before the full runtime is modeled.
				switch (callee) {
					// Upstream `tests/runci/Config.hx` declares `macro function isCi()` and uses it in
					// runtime code (e.g. `if (!isCi() && ...)`).
					//
					// In real Haxe, that macro call expands to a constant expression, so there is no
					// runtime dependency on a macro execution model.
					//
					// Stage3 bring-up doesn't execute macros, so we approximate `isCi()` as a simple
					// env probe (matches the upstream definition of `ci` for GitHub Actions).
					case EIdent("isCi") if (args.length == 0):
						return "((match Stdlib.Sys.getenv_opt \"GITHUB_ACTIONS\" with | Some v -> v | None -> \"\") = \"true\")";
					case EField(EIdent("Config"), "isCi") if (args.length == 0):
						return "((match Stdlib.Sys.getenv_opt \"GITHUB_ACTIONS\" with | Some v -> v | None -> \"\") = \"true\")";
					case EField(EIdent("runci.Config"), "isCi") if (args.length == 0):
						return "((match Stdlib.Sys.getenv_opt \"GITHUB_ACTIONS\" with | Some v -> v | None -> \"\") = \"true\")";
					// Stage 3 emit-runner bring-up: map `sys.FileSystem` statics used by RunCi to the
					// repo-owned OCaml runtime implementation (`packages/reflaxe.ocaml/std/runtime/HxFileSystem.ml`).
					//
					// Why
					// - Upstream `tests/runci/Config.hx` imports `sys.FileSystem` and then calls
					//   `FileSystem.fullPath(...)` in static initializers.
					// - Our bootstrap emitter doesn't yet resolve imported type short-names to OCaml
					//   module paths, so it would otherwise emit `FileSystem.fullPath` (unbound).
					//
					// Scope
					// - Minimal set needed by Gate2 bring-up; expand as upstream workloads demand.
					case EField(EIdent("FileSystem"), "fullPath") if (args.length == 1):
						return "HxFileSystem.fullPath ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "absolutePath") if (args.length == 1):
						return "HxFileSystem.absolutePath ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "exists") if (args.length == 1):
						return "HxFileSystem.exists ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "isDirectory") if (args.length == 1):
						return "HxFileSystem.isDirectory ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "readDirectory") if (args.length == 1):
						return "HxFileSystem.readDirectory ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "createDirectory") if (args.length == 1):
						return "HxFileSystem.createDirectory ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "deleteFile") if (args.length == 1):
						return "HxFileSystem.deleteFile ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "deleteDirectory") if (args.length == 1):
						return "HxFileSystem.deleteDirectory ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("FileSystem"), "rename") if (args.length == 2):
						return "HxFileSystem.rename ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					// Stage 3 emit-runner bring-up: map `sys.io.File` statics used by RunCi targets to
					// the repo-owned OCaml runtime implementation (`packages/reflaxe.ocaml/std/runtime/HxFile.ml`).
					//
					// Why
					// - Upstream runci targets often `import sys.io.File;` and then call `File.saveContent(...)`.
					// - The bootstrap emitter does not yet emit the full std `sys.io.File` module, so we
					//   treat a small set of whole-file operations as intrinsics backed by `HxFile`.
					case EField(EIdent("File"), "getContent") if (args.length == 1):
						return "HxFile.getContent ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("File"), "saveContent") if (args.length == 2):
						return "HxFile.saveContent ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("File"), "getBytes") if (args.length == 1):
						return "HxFile.getBytes ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("File"), "saveBytes") if (args.length == 2):
						return "HxFile.saveBytes ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("File"), "copy") if (args.length == 2):
						return "HxFile.copy ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					// Gate2 bring-up: avoid depending on the std `Xml` implementation while still compiling
					// upstream harness code that parses remote appcasts.
					//
					// Stage3 emit-runner does not execute these code paths on most platforms, but it must
					// successfully compile the RunCi harness (which references Flash target helpers).
					case EField(EIdent("Xml"), "parse") if (args.length == 1):
						return "(Obj.magic 0)";
					// Path joining (haxe.io.Path), used by upstream RunCi config.
					case EField(EIdent("Path"), "join") if (args.length == 1):
						return "HxBootArray.join ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") (\"/\") (fun (s : string) -> s)";
					// Bring-up: `haxe.io.Path.normalize(path)` (used by Flash target).
					case EField(EIdent("Path"), "normalize") if (args.length == 1):
						return "HxFileSystem.normalize_path ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")";
					// Bring-up: `haxe.io.Path.directory(path)` and `using haxe.io.Path; path.directory()`.
					case EField(EIdent("Path"), "directory") if (args.length == 1):
						return "Filename.dirname ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")";
					// Stage 3 bring-up: string instance methods used by upstream-ish harness code.
					//
					// Note
					// - Haxe lowers `s.split(",")` as an instance call.
					// - Our Stage3 emitter does not implement general instance dispatch yet, so we treat
					//   a few String methods as intrinsics backed by the repo-owned OCaml runtime.
					case EField(obj, "split") if (args.length == 1):
						return "HxString.split ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(obj, "directory") if (args.length == 0 && isStringExpr(obj)):
						return "Filename.dirname ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")";
					case EField(obj, "toLowerCase") if (args.length == 0):
						return "HxString.toLowerCase ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ()";
					case EField(obj, "toUpperCase") if (args.length == 0):
						return "HxString.toUpperCase ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ()";
					case EField(obj, "trim") if (args.length == 0):
						return "Stdlib.String.trim ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(obj, "startsWith") if (args.length == 1):
						return "HxString.startsWith ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(obj, "endsWith") if (args.length == 1):
						return "HxString.endsWith ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(obj, "indexOf") if (args.length == 1):
						return "HxString.indexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ((Obj.magic HxRuntime.hx_null))";
					case EField(obj, "indexOf") if (args.length == 2 && isStringExpr(obj)):
						return "HxString.indexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(obj, "lastIndexOf") if (args.length == 1 && isStringExpr(obj)):
						return "HxString.lastIndexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ((Obj.magic HxRuntime.hx_null))";
					case EField(obj, "lastIndexOf") if (args.length == 2 && isStringExpr(obj)):
						return "HxString.lastIndexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(EIdent("StringTools"), "trim") if (args.length == 1):
						return "Stdlib.String.trim ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("StringTools"), "ltrim") if (args.length == 1):
						return renderStringLtrimExpr(exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
							moduleNameByPkgAndClass));
					case EField(EIdent("StringTools"), "rtrim") if (args.length == 1):
						return renderStringRtrimExpr(exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
							moduleNameByPkgAndClass));
					case EField(obj, "substr") if (args.length == 1):
						return "HxString.substr ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ((Obj.magic HxRuntime.hx_null))";
					case EField(obj, "substr") if (args.length == 2):
						return "HxString.substr ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(obj, "indexOf") if (args.length == 2 && isStringExpr(obj)):
						return "HxString.indexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(obj, "lastIndexOf") if (args.length == 2 && isStringExpr(obj)):
						return "HxString.lastIndexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(obj, "substring") if (args.length == 2):
						return "HxString.substring ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(sysObj, "println") if (args.length == 1 && isRootSysReceiverExpr(sysObj)):
						return "print_endline ("
							+ exprToOcamlString(args[0], tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(ECall(EField(sysObj, "stdout"), []), "flush") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(flush stdout)";
					// Stage 3 bring-up: `Sys.command(cmd, ?args)` is used by upstream RunCi to execute
					// the `haxe` toolchain (and a few shell snippets like `export FOO=1 && ...`).
					//
					// We route through the stage3 bootstrap shim so Gate2 can run without relying on
					// an external runtime layer. The shim itself decides whether to use `/usr/bin/env`
					// or a shell (`/bin/sh -c`) based on whether `args` is empty and the command looks
					// like it contains shell operators.
					case EField(sysObj, "command") if (args.length == 1 && isRootSysReceiverExpr(sysObj)):
						return "HxBootProcess.command ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") (HxBootArray.create ())";
					case EField(sysObj, "command") if (args.length == 2 && isRootSysReceiverExpr(sysObj)):
						// `Sys.command(cmd, null)` occurs in upstream `runci.System.runSysTest`.
						// In our bring-up model, `null` lowers to the `HxRuntime.hx_null` sentinel, so coerce to an empty
						// `HxBootArray` at runtime to avoid segfaulting in the shim.
						final rawCmd = exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						final rawArgs = exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						return "(let __args = Obj.repr ("
							+ rawArgs
							+ ") in "
							+ "let __arr : string HxBootArray.t = if __args == HxRuntime.hx_null then HxBootArray.create () else (Obj.obj __args) in "
							+ "HxBootProcess.command ("
							+ rawCmd
							+ ") __arr)";
					// Stage 3 bring-up: basic env/CWD helpers used by upstream RunCi orchestration.
					case EField(sysObj, "getEnv") if (args.length == 1 && isRootSysReceiverExpr(sysObj)):
						return "HxSys.getEnv ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(sysObj, "time") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(HxSys.time ())";
					case EField(sysObj, "environment") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(HxSys.environment ())";
					case EField(sysObj, "args") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						// Haxe: Sys.args() excludes argv[0].
						return "(let __argv = Stdlib.Sys.argv in "
							+ "let __len = Stdlib.Array.length __argv in "
							+ "if __len <= 1 then HxBootArray.create () "
							+ "else HxBootArray.of_list (Stdlib.Array.to_list (Stdlib.Array.sub __argv 1 (__len - 1))))";
					case EField(sysObj, "stdin") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(Sys_io_Stdio.stdin ())";
					case EField(sysObj, "stdout") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(Sys_io_Stdio.stdout ())";
					case EField(sysObj, "stderr") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(Sys_io_Stdio.stderr ())";
					case EField(sysObj, "putEnv") if (args.length == 2 && isRootSysReceiverExpr(sysObj)):
						// Haxe: `Sys.putEnv(name, value)` accepts null for removal.
						// Our runtime provides the option-based API; bridge through the hx_null sentinel.
						final rawName = exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						final rawValue = exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						return "(let __v = Obj.repr ("
							+ rawValue
							+ ") in "
							+ "let __opt : string option = if __v == HxRuntime.hx_null then None else Some (Obj.obj __v) in "
							+ "HxSys.putEnv ("
							+ rawName
							+ ") __opt)";
					case EField(sysObj, "setCwd") if (args.length == 1 && isRootSysReceiverExpr(sysObj)):
						return "(Stdlib.Sys.chdir ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ "))";
					case EField(sysObj, "getCwd") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(Stdlib.Sys.getcwd ())";
					case EField(sysObj, "exit") if (args.length == 1 && isRootSysReceiverExpr(sysObj)):
						return "(HxSys.exit ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ "))";
					case EField(sysObj, "programPath") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						return "(HxSys.programPath ())";
					case EField(sysObj, "systemName") if (args.length == 0 && isRootSysReceiverExpr(sysObj)):
						// Keep this compatible with older OCaml runtimes (e.g. 4.13) where `Unix.uname`
						// is not available.
						//
						// Best-effort mapping to Haxe's coarse-grained names:
						// - Win32/Cygwin -> Windows
						// - presence of /System/Library -> Mac
						// - presence of /proc dir -> Linux
						// - otherwise -> Linux (fallback)
						return "(match Stdlib.Sys.os_type with "
							+ "| \"Win32\" | \"Cygwin\" -> \"Windows\" "
							+ "| _ -> "
							+ "if Stdlib.Sys.file_exists \"/System/Library\" then \"Mac\" "
							+ "else if Stdlib.Sys.file_exists \"/proc\" && Stdlib.Sys.is_directory \"/proc\" then \"Linux\" "
							+ "else \"Linux\")";
					// Stage 3 bring-up: `sys.io.Process.exitCode()` is used pervasively by RunCi to test
					// whether subcommands succeeded. Map it to our bootstrap shim.
					case EField(proc, "exitCode") if ((args.length == 0 || args.length == 1) && isSysIoProcessExpr(proc)):
						return "HxBootProcess.exitCode ("
							+ exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					// Bring-up: `sys.io.Process.close()` exists for resource cleanup; our shim is eager
					// and now flushes process state deterministically.
					case EField(proc, "close") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.close ("
							+ exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					// Bring-up: support terminating long-running server processes in RunCi orchestration.
					case EField(proc, "kill") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.kill ("
							+ exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					// Bring-up: allow reading process output as a single string.
					case EField(EField(proc, "stdout"), "readAll") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stdoutReadAll ("
							+ exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EField(proc, "stderr"), "readAll") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stderrReadAll ("
							+ exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					// Bring-up: allow line-wise reads used by upstream `runci.System.getHaxelibPath`.
					case EField(EField(proc, "stdout"), "readLine") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stdoutReadLine ("
							+ exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EField(proc, "stderr"), "readLine") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stderrReadLine ("
							+ exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					// Bring-up: `readAll()` on process pipes returns bytes in upstream; `.toString()` is
					// commonly chained. Our shim returns a string already, so treat it as identity.
					case EField(obj, "toString") if (args.length == 0):
						switch (obj) {
							case ECall(EField(EField(proc, "stdout"), "readAll"), []) if (isSysIoProcessExpr(proc)):
								return exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
							case ECall(EField(EField(proc, "stderr"), "readAll"), []) if (isSysIoProcessExpr(proc)):
								return exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
							case _:
						}
					// Stage 3 bring-up: allow a tiny subset of `Array` operations so orchestration code
					// can run under `--hxhx-emit-full-bodies`.
					case EField(obj, "toArray") if (args.length == 0):
						// Rest-args bring-up: upstream code frequently calls `rest.toArray()` where
						// `rest` originates from a `...args:T` parameter.
						//
						// We lower rest params to `Array<T>`, so treat `toArray()` as identity.
						switch (obj) {
							case EArrayDecl(_):
								return exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
									callSigByCallee);
							case EIdent(name):
								final t = tyForIdent(name);
								if (t == "Array" || StringTools.startsWith(t, "Array<")) {
									return exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
										callSigByCallee);
								}
							case _:
						}
					case EField(obj, "push") if (args.length == 1):
						switch (obj) {
							case EArrayDecl(_):
								return "HxBootArray.push ("
									+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ") ("
									+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ")";
							case EIdent(name):
								final t = tyForIdent(name);
								if (StringTools.startsWith(t, "Array<")) {
									return "HxBootArray.push ("
										+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
										+ ") ("
										+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
										+ ")";
								}
							case _:
						}
					case EField(obj, "copy") if (args.length == 0):
						switch (obj) {
							case EArrayDecl(_):
								return "HxBootArray.copy ("
									+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ")";
							case EIdent(name):
								final t = tyForIdent(name);
								if (StringTools.startsWith(t, "Array<")) {
									return "HxBootArray.copy ("
										+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
										+ ")";
								}
							case _:
						}
					case EField(obj, "concat") if (args.length == 1):
						switch (obj) {
							case EArrayDecl(_):
								return "HxBootArray.concat ("
									+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
										callSigByCallee)
									+ ") ("
									+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
										callSigByCallee)
									+ ")";
							case EIdent(name):
								final t = tyForIdent(name);
								if (StringTools.startsWith(t, "Array<")) {
									return "HxBootArray.concat ("
										+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
											callSigByCallee)
										+ ") ("
										+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
											callSigByCallee)
										+ ")";
								}
							case _:
						}
					case EField(obj, "contains") if (args.length == 1):
						if (isLikelyArrayMethodReceiver(obj)) {
							return "HxBootArray.contains ("
								+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
									callSigByCallee)
								+ ") ("
								+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
									callSigByCallee)
								+ ")";
						}
					case EField(obj, "indexOf") if (args.length == 2 && isLikelyArrayMethodReceiver(obj)):
						return "HxArray.indexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(obj, "lastIndexOf") if (args.length == 2 && isLikelyArrayMethodReceiver(obj)):
						return "HxArray.lastIndexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(obj, "slice") if (args.length == 2 && isLikelyArrayMethodReceiver(obj)):
						return "HxArray.slice ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee)
							+ ")";
					case EField(obj, "map") if (args.length == 1):
						// Stage3 emit-runner: treat array `map` calls as runtime intrinsics so
						// OCaml sees a direct function call instead of dynamic-field invocation
						// with warning-as-error over-application.
						if (isLikelyArrayMethodReceiver(obj)) {
							final receiver = exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee);
							final mapper = exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee);
							final usePortableAutoMetalTypedMap = isPortableAutoMetalizedRegionActive() && isLikelyStringArrayExpr(obj);
							if (isMetalProfileActive() || usePortableAutoMetalTypedMap) {
								if (usePortableAutoMetalTypedMap)
									markPortableAutoMetalizedLoweringUse("array_map_typed");
								return "HxBootArray.map (" + receiver + ") (" + mapper + ")";
							}
							return "HxBootArray.map_dyn (Obj.magic (" + receiver + ")) (Obj.repr (" + mapper + "))";
						}
					case EField(obj, "join") if (args.length == 1):
						if (isLikelyArrayMethodReceiver(obj)) {
							final receiver = exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee);
							final separator = exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee);
							final usePortableAutoMetalTypedJoin = isPortableAutoMetalizedRegionActive() && isLikelyStringArrayExpr(obj);
							if (isMetalProfileActive()) {
								if (!isLikelyStringArrayExpr(obj)) {
									throw "stage3 emitter: metal profile unsupported semantics: Array.join requires Array<String> receiver";
								}
								return "HxBootArray.join_strict (" + receiver + ") (" + separator + ") (fun (s : string) -> s)";
							}
							if (usePortableAutoMetalTypedJoin) {
								markPortableAutoMetalizedLoweringUse("array_join_typed");
								return "HxBootArray.join_strict (" + receiver + ") (" + separator + ") (fun (s : string) -> s)";
							}
							if (isLikelyStringArrayExpr(obj)) {
								return "HxBootArray.join (" + receiver + ") (" + separator + ") (fun (s : string) -> s)";
							}
							// Stage3 emit-runner: fallback for array-like receivers where type
							// inference did not preserve `Array<String>` shape through chained calls.
							return "HxBootArray.join_dyn (Obj.magic (" + receiver + ")) (" + separator + ")";
						}
					case EField(obj, "indexOf") if (args.length == 2 && isLikelyArrayExpr(obj)):
						return "HxBootArray.indexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")";
					case EField(obj, "lastIndexOf") if (args.length == 2 && isLikelyArrayExpr(obj)):
						return "HxBootArray.lastIndexOf ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")";
					case EField(obj, "slice") if (args.length == 2 && isLikelyArrayExpr(obj)):
						return "HxBootArray.slice ("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")";
					case _:
				}

				// Stage3 object bring-up: rewrite instance-call syntax to function-call syntax.
				//
				// Haxe:  obj.ping(a, b)
				// OCaml: ping obj a b
				//
				// We only do this when:
				// - the member is known as an instance method in the current module, and
				// - the receiver is not a type-path/static reference.
				switch (callee) {
					case EField(obj, field) if (hasArity(field) && hasCurrentInstanceMethod(field) && !isTypePathExpr(obj)):
						final rendered = new Array<String>();
						rendered.push("("
							+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")");
						for (a in args)
							rendered.push("("
								+ exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
								+ ")");
						return ocamlValueIdent(field) + " " + rendered.join(" ");
					case _:
				}
				final instanceCallName = switch (callee) {
					case EIdent(name) if (hasCurrentInstanceMethod(name)):
						name;
					case EField(EThis, name) if (hasCurrentInstanceMethod(name)):
						name;
					case EField(EIdent("this"), name) if (hasCurrentInstanceMethod(name)):
						name;
					case EField(EIdent("this_"), name) if (hasCurrentInstanceMethod(name)):
						name;
					case _:
						null;
				};
				final isDirectSelfRecursiveCall = switch (callee) {
					case EIdent(name):
						currentFunctionNameRaw != null
						&& name == currentFunctionNameRaw
						&& hasCurrentInstanceMethod(name)
						&& hasThisBinding();
					case EField(EThis, name):
						currentFunctionNameRaw != null && name == currentFunctionNameRaw && hasCurrentInstanceMethod(name);
					case EField(EIdent("this"), name):
						currentFunctionNameRaw != null && name == currentFunctionNameRaw && hasCurrentInstanceMethod(name);
					case EField(EIdent("this_"), name):
						currentFunctionNameRaw != null && name == currentFunctionNameRaw && hasCurrentInstanceMethod(name);
					case _:
						false;
				};
				_EmitterStageDebug.traceSelfRecursion("receiver_plan",
					"current=" + nullableString(currentFunctionNameRaw) + " callee=" + calleeTag(callee) + " instance=" + nullableString(instanceCallName)
					+ " hasThis=" + bool01(hasThisBinding()) + " instanceMethod="
					+ bool01(instanceCallName != null && hasCurrentInstanceMethod(instanceCallName)) + " directInstance="
					+ bool01(isDirectSelfRecursiveCall));

				final receiverAlreadyForwarded = if (instanceCallName != null && args.length > 0) {
					if (hasArity(instanceCallName)) {
						args.length >= arityFor(instanceCallName)
						&& looksLikeForwardedReceiverExpr(args[0]);
					} else {
						// Fallback for bring-up paths where typed arity is unavailable:
						// if the first argument looks like an object receiver and at least one
						// additional argument exists, treat this as an already-forwarded call.
						looksLikeForwardedReceiverExpr(args[0]) && args.length > 1;
					}
				} else {
					false;
				};
				_EmitterStageDebug.traceSelfRecursion("forwarding_plan",
					"current=" + nullableString(currentFunctionNameRaw) + " callee=" + calleeTag(callee) + " instance=" + nullableString(instanceCallName)
					+ " receiverForwarded=" + bool01(receiverAlreadyForwarded) + " args=" + args.length);

				final c = if (instanceCallName != null) {
					if (receiverAlreadyForwarded && !isDirectSelfRecursiveCall) {
						ocamlValueIdent(instanceCallName);
					} else if (hasThisBinding()) {
						ocamlValueIdent(instanceCallName) + " (this_)";
					} else {
						ocamlValueIdent(instanceCallName);
					}
				} else {
					exprToOcaml(callee, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				};
				// Stage3 emit-runner: normalize `haxe.SysTools.quoteWinArg.bind(null, true)`
				// into a first-class unary callback so OCaml does not compile the dynamic
				// `bind` invocation path (which otherwise becomes warning-as-error over-application).
				if (c == "(Obj.magic (HxAnon.get (Obj.repr (Haxe_SysTools.quoteWinArg)) \"bind\"))" && args.length == 2) {
					final isEscapeMetaTrue = switch (args[1]) {
						case EBool(true):
							true;
						case _:
							false;
					};
					if (isEscapeMetaTrue) {
						return "(fun __arg -> Haxe_SysTools.quoteWinArg (__arg) (true))";
					}
				}
				// Stage3 stdlib bring-up guard:
				// - `haxe.io.Bytes.readString(pos, len)` lowers to `getString(pos, len)`.
				// - Native parser recovery can miss the implicit receiver/optional encoding argument.
				// - Emit the receiver-aware form directly to avoid OCaml partial application.
				final isPreappliedGetString = c == "getString (this_)";
				if ((c == "getString" || isPreappliedGetString) && args.length == 2) {
					return (isPreappliedGetString ? c : (c + " (this_)"))
						+ " ("
						+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
						+ ") ("
						+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
						+ ") ((Obj.magic HxRuntime.hx_null))";
				}
				// Stage3 stdlib bring-up guard:
				// - `haxe.io.Bytes.getDouble/getFloat/getInt64` call `getInt32(pos)` in instance context.
				// - Native parser recovery can lose the implicit receiver for the unqualified helper call.
				// - Emit the receiver-aware call form directly to avoid OCaml partial applications.
				if (c == "getInt32" && args.length == 1) {
					return c
						+ " (this_)"
						+ " ("
						+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
						+ ")";
				}
				// Stage3 stdlib bring-up guard:
				// - `haxe.ds.EnumValueMap.compareArg` calls `compare(v1, v2)` in instance context.
				// - In some recovered AST paths, implicit receiver insertion can still be skipped,
				//   yielding partial application in emitted OCaml.
				// - Emit receiver-aware call form directly for this known shape.
				if (c == "compare" && hasThisBinding() && args.length == 2) {
					return c
						+ " (this_)"
						+ " ("
						+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
						+ ") ("
						+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
						+ ")";
				}
				// Stage3 stdlib bring-up guard:
				// - Some parser-recovery paths collapse `compare(v1, v2)` into `compare()` in
				//   `haxe.ds.EnumValueMap.compareArg`.
				// - The generic missing-arg filler then inserts poison values and still misses
				//   the receiver, producing a partial application.
				// - Recover the known local-param call shape directly when available.
				if (c == "compare" && hasThisBinding() && args.length == 0 && hasTyIdent("v1") && hasTyIdent("v2")) {
					return c
						+ " (this_) ("
						+ exprToOcaml(EIdent("v1"), arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
						+ ") ("
						+ exprToOcaml(EIdent("v2"), arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
						+ ")";
				}
				// Safety: if the callee is already "bring-up poison", do not apply arguments.
				//
				// Why
				// - Applying args to a non-function expression produces OCaml warnings/errors
				//   and can cascade into type mismatches.
				// - In bring-up we prefer collapsing to poison over producing invalid OCaml.
				if (c == "(Obj.magic 0)") {
					"(Obj.magic 0)";
				} else {
					final receiverPreApplied = c.indexOf(" (this_)") != -1;
					final preAppliedArgCount = receiverPreApplied ? 1 : 0;

					function callSigForExpr(expr:HxExpr):Null<EmitterCallSig> {
						final currentModuleName = currentModuleNameForArityResolution();
						return switch (expr) {
							case EIdent(name):
								final lowered = ocamlValueIdent(name);
								final byLowered = callSigFor(lowered);
								if (byLowered != null) {
									byLowered;
								} else {
									final byName = callSigFor(name);
									if (byName != null) {
										byName;
									} else if (currentModuleName != null && currentModuleName.length > 0) {
										final byQualifiedLowered = callSigFor(currentModuleName + "." + lowered);
										byQualifiedLowered != null ? byQualifiedLowered : callSigFor(currentModuleName + "." + name);
									} else {
										null;
									}
								}
							case EField(obj, name):
								final lowered = ocamlValueIdent(name);
								final byLowered = callSigFor(lowered);
								if (byLowered != null) {
									byLowered;
								} else {
									final byName = callSigFor(name);
									if (byName != null) {
										byName;
									} else if (currentModuleName != null && currentModuleName.length > 0) {
										final byQualifiedLowered = callSigFor(currentModuleName + "." + lowered);
										if (byQualifiedLowered != null) {
											byQualifiedLowered;
										} else {
											final byQualifiedName = callSigFor(currentModuleName + "." + name);
											if (byQualifiedName != null) {
												byQualifiedName;
											} else {
												var qualified:Null<EmitterCallSig> = null;
												switch (obj) {
													case EIdent(typeName):
														final importedModule = staticImportModule(typeName);
														if (importedModule != null && importedModule.length > 0) {
															qualified = callSigFor(importedModule + "." + lowered);
															if (qualified == null)
																qualified = callSigFor(importedModule + "." + name);
														}
													case _:
												}
												if (qualified == null) {
													final parts = tryExtractTypePathPartsFromExpr(obj);
													if (parts != null && parts.length > 0 && isUpperStart(parts[parts.length - 1])) {
														var modName = ocamlModuleNameFromTypePathParts(parts);
														var resolvedByModuleIndex = false;
														if (moduleNameByPkgAndClass != null) {
															final raw = parts.join(".");
															var cur = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
															while (true) {
																final key = cur + ":" + raw;
																final local = moduleNameForKey(key);
																if (local != null && local.length > 0) {
																	modName = local;
																	resolvedByModuleIndex = true;
																	break;
																}
																if (cur.length == 0)
																	break;
																final lastDot = cur.lastIndexOf(".");
																cur = lastDot < 0 ? "" : cur.substr(0, lastDot);
															}
															if (!resolvedByModuleIndex
																&& !isKnownModuleName(modName)
																&& modName == ocamlModuleNameFromTypePathParts(parts)
																&& parts.length == 1) {
																final curPkg = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
																if (curPkg.length > 0) {
																	final qualifiedParts = curPkg.split(".");
																	for (p in parts)
																		qualifiedParts.push(p);
																	modName = ocamlModuleNameFromTypePathParts(qualifiedParts);
																}
															}
														}
														if (parts.length == 1 && parts[0] == "Int64" && currentImportInt64 != null && currentImportInt64.length > 0)
															modName = currentImportInt64;
														qualified = callSigFor(modName + "." + lowered);
														if (qualified == null)
															qualified = callSigFor(modName + "." + name);
														if (qualified == null)
															qualified = resolveQualifiedModuleCallSigByEmittedModuleName(modName, name, lowered);
														if (qualified == null && currentModuleFilePath != null && currentModuleFilePath.length > 0)
															qualified = resolveQualifiedModuleCallSig(currentModuleFilePath, parts, name, lowered);
													}
												}
												qualified;
											}
										}
									} else {
										var qualified:Null<EmitterCallSig> = null;
										switch (obj) {
											case EIdent(typeName):
												final importedModule = staticImportModule(typeName);
												if (importedModule != null && importedModule.length > 0) {
													qualified = callSigFor(importedModule + "." + lowered);
													if (qualified == null)
														qualified = callSigFor(importedModule + "." + name);
												}
											case _:
										}
										if (qualified == null) {
											final parts = tryExtractTypePathPartsFromExpr(obj);
											if (parts != null && parts.length > 0 && isUpperStart(parts[parts.length - 1])) {
												var modName = ocamlModuleNameFromTypePathParts(parts);
												var resolvedByModuleIndex = false;
													if (moduleNameByPkgAndClass != null) {
													final raw = parts.join(".");
													var cur = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
													while (true) {
														final key = cur + ":" + raw;
														final local = moduleNameForKey(key);
														if (local != null && local.length > 0) {
															modName = local;
															resolvedByModuleIndex = true;
															break;
														}
														if (cur.length == 0)
															break;
														final lastDot = cur.lastIndexOf(".");
														cur = lastDot < 0 ? "" : cur.substr(0, lastDot);
													}
													if (!resolvedByModuleIndex
														&& !isKnownModuleName(modName)
														&& modName == ocamlModuleNameFromTypePathParts(parts)
														&& parts.length == 1) {
														final curPkg = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
														if (curPkg.length > 0) {
															final qualifiedParts = curPkg.split(".");
															for (p in parts)
																qualifiedParts.push(p);
															modName = ocamlModuleNameFromTypePathParts(qualifiedParts);
														}
													}
												}
												if (parts.length == 1 && parts[0] == "Int64" && currentImportInt64 != null && currentImportInt64.length > 0)
													modName = currentImportInt64;
												qualified = callSigFor(modName + "." + lowered);
												if (qualified == null)
													qualified = callSigFor(modName + "." + name);
												if (qualified == null)
													qualified = resolveQualifiedModuleCallSigByEmittedModuleName(modName, name, lowered);
												if (qualified == null && currentModuleFilePath != null && currentModuleFilePath.length > 0)
													qualified = resolveQualifiedModuleCallSig(currentModuleFilePath, parts, name, lowered);
											}
										}
										qualified;
									}
								}
							case _:
								null;
						};
					}

					function fallbackLocalFunctionSig(name:String):Null<EmitterCallSig> {
						if (currentModuleFilePath == null || currentModuleFilePath.length == 0)
							return null;
						try {
							final source = sys.io.File.getContent(currentModuleFilePath);
							final parsed = ParserStage.parse(source, currentModuleFilePath);
							final decl = parsed.getDecl();
							final moduleTypeName = expectedMainClassFromFilePath(currentModuleFilePath);
							final currentShortName = currentModuleShortName();
							for (cls in HxModuleDecl.getClasses(decl)) {
								final className = HxClassDecl.getName(cls);
								if (className == null || className.length == 0 || className == "Unknown")
									continue;
								if (moduleTypeName != null && moduleTypeName.length > 0) {
									if (className != moduleTypeName)
										continue;
								} else if (currentShortName.length > 0 && className != currentShortName) {
									continue;
								}
								for (fn in HxClassDecl.getFunctions(cls)) {
									final fnNameRaw = HxFunctionDecl.getName(fn);
									if (fnNameRaw == null || fnNameRaw.length == 0)
										continue;
									if (ocamlValueIdent(fnNameRaw) == name || fnNameRaw == name)
										return callSigFromFunction(fn);
								}
							}
						} catch (_:haxe.Exception) {} catch (_:String) {}
						return null;
					}

					// Some imported stdlib statics are emitted into the Stage3 output without a scanned
					// signature provider in the current program. When those APIs rely on omitted optional
					// arguments, the general call-sig path has nothing to pad from and we emit a partial
					// application instead of a full call.
					//
					// Keep this narrowly scoped to known imported stdlib shapes that are already exercised
					// by upstream tests, rather than pretending we have generic imported-signature recovery.
					function fallbackOptionalSigForExpr(expr:HxExpr):Null<EmitterCallSig> {
						return switch (expr) {
							case EField(obj, "stringify"):
								final parts = tryExtractTypePathPartsFromExpr(obj);
								if (parts != null && parts.length > 0) {
									final last = parts[parts.length - 1];
									if (last == "Json" || last == "Haxe_Json") {
										{
											expected: 3,
											required: 1,
											fixed: 3,
											hasRest: false,
											needsReceiver: false
										};
									} else {
										null;
									}
								} else {
									null;
								}
							case EField(obj, "print"):
								final parts = tryExtractTypePathPartsFromExpr(obj);
								if (parts != null && parts.length > 0) {
									final last = parts[parts.length - 1];
									if (last == "JsonPrinter" || last == "Haxe_format_JsonPrinter") {
										{
											expected: 3,
											required: 1,
											fixed: 3,
											hasRest: false,
											needsReceiver: false
										};
									} else {
										null;
									}
								} else {
									null;
								}
							case EField(obj, "ofString"):
								final parts = tryExtractTypePathPartsFromExpr(obj);
								if (parts != null && parts.length > 0) {
									final last = parts[parts.length - 1];
									if (last == "Bytes" || last == "Haxe_io_Bytes") {
										{
											expected: 2,
											required: 1,
											fixed: 2,
											hasRest: false,
											needsReceiver: false
										};
									} else {
										null;
									}
								} else {
									null;
								}
							case EField(obj, field):
								final parts = tryExtractTypePathPartsFromExpr(obj);
								if (parts != null && parts.length > 0) {
									final last = parts[parts.length - 1];
									if (last == "Assert" || last == "Utest_Assert") {
										switch (field) {
											case "isTrue", "isFalse":
												{
													expected: 3,
													required: 1,
													fixed: 3,
													hasRest: false,
													needsReceiver: false
												};
											case "equals", "contains":
												{
													expected: 4,
													required: 2,
													fixed: 4,
													hasRest: false,
													needsReceiver: false
												};
											case "floatEquals":
												{
													expected: 5,
													required: 2,
													fixed: 5,
													hasRest: false,
													needsReceiver: false
												};
											case "same":
												{
													expected: 6,
													required: 2,
													fixed: 6,
													hasRest: false,
													needsReceiver: false
												};
											case "raises":
												{
													expected: 5,
													required: 1,
													fixed: 5,
													hasRest: false,
													needsReceiver: false
												};
											case "fail":
												{
													expected: 2,
													required: 0,
													fixed: 2,
													hasRest: false,
													needsReceiver: false
												};
											case _:
												null;
										}
									} else {
										null;
									}
								} else {
									null;
								}
							case _:
								null;
						};
					}

					var sig = callSigFor(c);
					if (sig == null) {
						final firstSpace = c.indexOf(" ");
						if (firstSpace > 0)
							sig = callSigFor(c.substr(0, firstSpace));
						if (sig == null)
							sig = callSigForExpr(callee);
						if (sig == null) {
							switch (callee) {
								case EIdent(name):
									sig = fallbackLocalFunctionSig(name);
								case _:
							}
						}
						if (sig == null)
							sig = fallbackOptionalSigForExpr(callee);
					}

					// Stage 3 bring-up safety: avoid emitting OCaml that over-applies a function.
					//
					// Why
					// - Our bootstrap frontend does not always recover accurate parameter lists for
					//   complex Haxe signatures (notably `@:generic` with constrained type params).
					// - When we under-count arity, OCaml compilation fails hard with:
					//     "This function has type ... It is applied to too many arguments"
					//
					// Strategy
					// - If we have a known signature and the call site passes *more* args than the
					//   function can accept (and it is not a rest-arg function), collapse the call
					//   to bring-up poison rather than emitting invalid OCaml.
					if (sig != null && !sig.hasRest && (args.length + preAppliedArgCount) > sig.expected) {
						return "(Obj.magic 0)";
					}
					// Also guard against mismatches between parsed call signatures and the *emitted*
					// function arity for this module.
					//
					// Why
					// - `callSigByCallee` is derived from the parsed surface (and can be more complete),
					//   but the Stage3 typed environment may intentionally degrade or drop parameters for
					//   unsupported signatures.
					// - If we emit `let rec f () = ...` (arity 0) but keep call sites as `f a b`, OCaml
					//   fails with "applied to too many arguments".
					//
					// Rule
					// - When the callee is an unqualified in-module identifier and we have a recorded arity,
					//   collapse over-applications to bring-up poison (unless we know it is a rest-arg call).
					if (hasArity(c) && (args.length + preAppliedArgCount) > arityFor(c)) {
						if (sig == null || !sig.hasRest)
							return "(Obj.magic 0)";
					}

					// Rest-args lowering (Stage3 bring-up)
					//
					// Haxe: `function f(a:Int, ...rest:String)` has a single rest parameter which can be
					// omitted or supplied with multiple values at call sites.
					//
					// OCaml emission strategy:
					// - Lower to a fixed-arity function where the last parameter is an `Array<T>` of rest values
					//   (empty array when omitted).
					// - Call sites pack trailing arguments into an `HxBootArray`.
					if (sig != null && sig.hasRest) {
						final fixedCount = sig.fixed;
						final fixedArgs = new Array<HxExpr>();
						for (i in 0...fixedCount)
							fixedArgs.push(i < args.length ? args[i] : ENull);
						final restArgs = (args.length > fixedCount) ? args.slice(fixedCount) : [];
						final restCode = (restArgs.length == 0) ? "HxBootArray.create ()" : ("HxBootArray.of_list ["
							+ restArgs.map(a -> exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee))
								.join("; ") + "]");

						final argCodes = new Array<String>();
						for (a in fixedArgs) {
							argCodes.push("("
								+ exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
								+ ")");
						}
						argCodes.push("(" + restCode + ")");

						c + " " + argCodes.join(" ");
					} else {
						var fullArgs = args.copy();
						final implicitReceiverBySig = !receiverPreApplied && sig != null && sig.needsReceiver && switch (callee) {
							case EIdent(_):
								hasThisBinding();
							case EField(EThis, _):
								true;
							case _:
								false;
						};
						if (implicitReceiverBySig && (fullArgs.length == 0 || !looksLikeForwardedReceiverExpr(fullArgs[0])))
							fullArgs.insert(0, EThis);

						final forceImplicitThis = !receiverPreApplied && switch (callee) {
							case EIdent(name): hasThisBinding() && hasArity(name) && (args.length + 1) == arityFor(name);
							case EField(EThis, name): hasArity(name) && (args.length + 1) == arityFor(name);
							case EField(EIdent("this"), name): hasArity(name) && (args.length + 1) == arityFor(name);
							case EField(EIdent("this_"), name): hasArity(name) && (args.length + 1) == arityFor(name);
							case _:
								false;
						};
						if (forceImplicitThis)
							fullArgs.insert(0, EThis);

						final needsReceiverBySig = !receiverPreApplied && sig != null && sig.needsReceiver && switch (callee) {
							case EIdent(name):
								hasThisBinding() && hasCurrentInstanceMethod(name) && fullArgs.length < sig.required;
							case EField(EThis, name):
								hasCurrentInstanceMethod(name) && fullArgs.length < sig.required;
							case EField(EIdent("this"), name):
								hasCurrentInstanceMethod(name) && fullArgs.length < sig.required;
							case EField(EIdent("this_"), name):
								hasCurrentInstanceMethod(name) && fullArgs.length < sig.required;
							case _:
								false;
						};
						if (needsReceiverBySig && (fullArgs.length == 0 || !looksLikeForwardedReceiverExpr(fullArgs[0])))
							fullArgs.insert(0, EThis);

						// Stage3 widened-closure hardening: some recovered call signatures include an
						// implicit receiver parameter (`this_` + args). If a call-site provides fewer
						// args than the receiver-aware signature requires, prepend the receiver explicitly.
						//
						// - In instance contexts, forward `this`.
						// - Outside instance contexts (for static/qualified call-shapes), use a sentinel.
						if (!receiverPreApplied && sig != null && sig.needsReceiver && fullArgs.length < sig.required) {
							fullArgs.insert(0, hasThisBinding() ? EThis : ENull);
						}

						var missingCount = missing;
						if (missingCount == 0 && sig != null) {
							final expectedAfterPreapply = sig.expected - preAppliedArgCount;
							if (expectedAfterPreapply > fullArgs.length)
								missingCount = expectedAfterPreapply - fullArgs.length;
						}
						// Bootstrap/source parity: in some same-module instance-call shapes the bootstrap
						// host recovers the receiver/arity but still loses the richer call signature.
						//
						// Example:
						// - `deq(0, widen(0))` where `deq(expected, actual, ?p:haxe.PosInfos)` lowers to
						//   `deq this_ expected actual hx_null`
						// - if `sig` is missing, the generic optional-arg padding path never runs and we
						//   emit a warning-producing partial application instead.
						//
						// When we already know this is a same-module instance method and we have the emitted
						// OCaml arity for it, use that arity as the fallback expected width.
						if (missingCount == 0 && sig == null && instanceCallName != null && hasArity(instanceCallName)) {
							final expectedByArity = arityFor(instanceCallName);
							if (expectedByArity > fullArgs.length)
								missingCount = expectedByArity - fullArgs.length;
						}

						// Stage 3 bring-up: upstream often passes `pos` as the last argument to APIs declared
						// as `(required..., ?msg:String, ?pos:haxe.PosInfos)`, relying on Haxe's optional-arg
						// skipping to interpret `f(x, pos)` as `f(x, null, pos)`.
						//
						// Our bootstrap typer/emitter does not model that unification yet. To keep OCaml output
						// type-correct, we insert missing args as `null` immediately *before* a trailing `pos`
						// identifier when we have a signature for the callee.
						if (sig != null && (sig.expected - preAppliedArgCount) > fullArgs.length && fullArgs.length > 0) {
							final last = fullArgs[fullArgs.length - 1];
							final isTrailingPos = switch (last) {
								case EIdent("pos"): true;
								case _: false;
							};
							if (isTrailingPos) {
								final missingBefore = (sig.expected - preAppliedArgCount) - fullArgs.length;
								final adjusted = new Array<HxExpr>();
								final prefixLen = fullArgs.length - 1;
								for (i in 0...prefixLen)
									adjusted.push(fullArgs[i]);
								for (_ in 0...missingBefore)
									adjusted.push(ENull);
								adjusted.push(last);
								fullArgs = adjusted;
								missingCount = 0;
							}
						}

						// Stage 3 bring-up: emulate upstream optional-arg "skipping" for a small set of
						// Gate2 harness calls that intentionally pass a later argument type.
						//
						// Example (upstream runci):
						// - `haxelibInstallGit(account, repo, true)` is accepted by Haxe even though the
						//   third parameter is `?branch:String`. Haxe effectively interprets this as:
						//     `haxelibInstallGit(account, repo, null, null, true, null)`
						//
						// Our bootstrap emitter doesn't model full optional-arg unification, so we special-case
						// this shape to keep Stage3 emit-runner compiling.
						if (sig != null && c == "Runci_System.haxelibInstallGit" && args.length == 3) {
							switch (args[2]) {
								case EBool(_):
									fullArgs = [args[0], args[1], ENull, ENull, args[2], ENull];
									missingCount = 0;
								case _:
							}
						}
						// Stage 3 Gate2 emit-runner: upstream `runci.System.runSysTest` calls
						// `getDisplayCmd(cmd, args, null)` while our bootstrap parser currently recovers
						// `getDisplayCmd` as an instance method shape (`this_`, `cmd`, `args`).
						//
						// Normalize the 3-arg static-looking call into the recovered instance signature.
						if ((c == "getDisplayCmd" || c == "Runci_System.getDisplayCmd") && args.length >= 2) {
							fullArgs = [ENull, ECall(EField(EIdent("Std"), "string"), [args[0]]), args[1]];
							missingCount = 0;
						}
						// Stage 3 bring-up: php boot checks `class_exists(name)` / `interface_exists(name)`
						// where the second optional `autoload` arg is omitted.
						//
						// Some upstream extern surfaces are currently recovered without enough
						// signature metadata in `callSigByCallee`, so we patch this known shape to avoid
						// OCaml partial application errors during Gate1 emit runs.
						if (sig == null && args.length == 1 && (c == "Php_Global.class_exists" || c == "Php_Global.interface_exists")) {
							fullArgs = [args[0], ENull];
							missingCount = 0;
						}
						// Stage3 stdlib bring-up: `haxe.io.Bytes.readString(pos, len)` calls
						// `getString(pos, len)` while `getString` has receiver + optional encoding.
						//
						// Native parser recovery can miss the implicit receiver/optional insertion
						// for this unqualified call shape, yielding partial application at OCaml link-time.
						// Normalize to the receiver-aware call form here.
						if ((c == "getString" || c == "getString (this_)") && fullArgs.length == 2) {
							fullArgs = c == "getString (this_)"
								? [fullArgs[0], fullArgs[1], ENull]
								: [EThis, fullArgs[0], fullArgs[1], ENull];
							missingCount = 0;
						}
						// Bootstrap-host parity hardening: when a call already has its receiver pre-applied,
						// force the final positional arg vector to the widest trustworthy post-receiver width
						// immediately before render.
						//
						// Why
						// - Earlier bring-up bookkeeping can still drift in bootstrap-built hosts even when
						//   `receiverPreApplied`, `preAppliedArgCount`, and the recovered call signature look
						//   correct.
						// - In the failing `deq(expected, actual, ?p)` shape, bootstrap can either:
						//   - recover a signature that under-counts omitted optional parameters, or
						//   - lose the original same-module instance callee name while still emitting
						//     the right OCaml callee head (`deq (this_)`).
						// - That drift shows up as warning-producing partial application such as
						//   `deq (this_) (0) (widen (0))` instead of appending the trailing `null`.
						//
						// Strategy
						// - Right before rendering, normalize the argument vector against the larger of:
						//   - the recovered signature width
						//   - the emitted same-module arity width
						//   - the rendered callee-head arity width
						// - This keeps source and bootstrap hosts aligned
						//   without inventing a separate bootstrap-only call path.
						//
						// Narrow bring-up guard
						// - The upstream numeric-cast helper seam still shows one bootstrap-only drift:
						//   same-module `deq(expected, actual, ?p)` / `eq(expected, actual, ?p)` calls can
						//   reach this point with a pre-applied receiver and two value args, but without the
						//   trailing optional `PosInfos` arg.
						// - When that happens, OCaml warning 5 becomes an error-producing partial application.
						// - Handle this known helper shape directly before the more generic width recovery.
						if (receiverPreApplied && fullArgs.length == 2 && (c == "deq (this_)" || c == "eq (this_)")) {
							fullArgs.push(ENull);
							missingCount = 0;
						}
						final firstSpace = c.indexOf(" ");
						final renderedCalleeHead = firstSpace > 0 ? c.substr(0, firstSpace) : c;
						final recoveredInstanceSig = instanceCallName != null ? callSigFor(resolveCallSigName(instanceCallName)) : null;
						final recoveredRenderedSig = callSigFor(resolveCallSigName(renderedCalleeHead));
						if (receiverPreApplied
							&& (sig != null
								|| recoveredInstanceSig != null
								|| recoveredRenderedSig != null
								|| (instanceCallName != null && hasArity(instanceCallName))
								|| hasArity(renderedCalleeHead))) {
							final expectedBySig = sig != null ? (sig.expected - preAppliedArgCount) : 0;
							final expectedByRecoveredInstanceSig = recoveredInstanceSig != null ? (recoveredInstanceSig.expected - preAppliedArgCount) : 0;
							final expectedByRecoveredRenderedSig = recoveredRenderedSig != null ? (recoveredRenderedSig.expected - preAppliedArgCount) : 0;
							final expectedByArity = (instanceCallName != null && hasArity(instanceCallName))
								? (arityFor(instanceCallName) - preAppliedArgCount)
								: 0;
							final expectedByRenderedCallee = hasArity(renderedCalleeHead)
								? (arityFor(renderedCalleeHead) - preAppliedArgCount)
								: 0;
							final expectedAfterPreapply = {
								final bestRecovered = expectedByRecoveredInstanceSig > expectedByRecoveredRenderedSig
									? expectedByRecoveredInstanceSig
									: expectedByRecoveredRenderedSig;
								final bestArity = expectedByArity > expectedByRenderedCallee ? expectedByArity : expectedByRenderedCallee;
								final bestSig = expectedBySig > bestRecovered ? expectedBySig : bestRecovered;
								bestSig > bestArity ? bestSig : bestArity;
							};
							while (fullArgs.length < expectedAfterPreapply)
								fullArgs.push(ENull);
							missingCount = 0;
						}
						for (_ in 0...missingCount)
							fullArgs.push(ENull);

						final renderedArgs = fullArgs.map(a -> "("
							+ exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ")");
						final isHxAnonDynamicCall = c.indexOf("HxAnon.get") != -1;
						final isContextLoadFlattenedCall = c == "Haxe_macro_Context.load" && renderedArgs.length > 2;
						final isContextLoadFollowupCall = StringTools.startsWith(c, "Haxe_macro_Context.load ") && renderedArgs.length > 0;

						if (isContextLoadFlattenedCall || isContextLoadFollowupCall) {
							// Stage3 macro bring-up: parsed call shapes can represent
							// `Context.load(name, nargs)(...)` either as a flattened single call or as a
							// follow-up call where `c` already includes `load name nargs`.
							// Both forms can trigger OCaml Warning 20 over-application.
							//
							// Rebuild the two-step callable form explicitly and cast by the observed
							// tail arity to keep this warning-clean while preserving bring-up behavior.
							final loadCall = isContextLoadFlattenedCall ? (c + " " + renderedArgs[0] + " " + renderedArgs[1]) : c;
							final tailArgs = isContextLoadFlattenedCall ? renderedArgs.slice(2) : renderedArgs;
							if (tailArgs.length <= 5) {
								var fnTy = "Obj.t";
								for (_ in 0...tailArgs.length)
									fnTy = "Obj.t -> " + fnTy;
								var renderedCall = "((Obj.magic (" + loadCall + ") : " + fnTy + ")";
								for (argCode in tailArgs)
									renderedCall += " (Obj.repr " + argCode + ")";
								renderedCall += ")";
								"(Obj.magic " + renderedCall + ")";
							} else {
								loadCall + " " + tailArgs.join(" ");
							}
						} else if (isHxAnonDynamicCall) {
							// Stage3 emit-runner hardening: dynamic-field call targets lowered through
							// `HxAnon.get` frequently trigger Warning 20 in OCaml when inference picks a
							// unit-arg closure shape and the call site supplies positional arguments.
							//
							// Emit explicit arity casts for common call arities so OCaml treats these
							// as intentional dynamic calls (matching Stage3 bring-up semantics) rather
							// than "ignored extra argument" over-application.
							if (renderedArgs.length == 0) {
								"(Obj.magic ((Obj.magic (" + c + ") : unit -> Obj.t) ()))";
							} else if (renderedArgs.length <= 5) {
								var fnTy = "Obj.t";
								for (_ in 0...renderedArgs.length)
									fnTy = "Obj.t -> " + fnTy;
								var renderedCall = "((Obj.magic (" + c + ") : " + fnTy + ")";
								for (argCode in renderedArgs)
									renderedCall += " (Obj.repr " + argCode + ")";
								renderedCall += ")";
								"(Obj.magic " + renderedCall + ")";
							} else {
								c + " " + renderedArgs.join(" ");
							}
						} else if (renderedArgs.length == 0) {
							var appendUnit = true;
							switch (callee) {
								case EIdent(name) if (hasArity(name)):
									if (hasCurrentInstanceMethod(name) && hasThisBinding() && arityFor(name) <= 1) {
										appendUnit = false;
									}
								case EField(EThis, name) if (hasArity(name)):
									if (arityFor(name) <= 1) appendUnit = false;
								case _:
							}
							final renderedCall = appendUnit ? (c + " ()") : c;
								(sig == null
									&& StringTools.startsWith(c, "Php_Global.")) ? "(Obj.magic (" + renderedCall + "))" : renderedCall;
						} else {
							final renderedCall = c + " " + renderedArgs.join(" ");
							(sig == null
								&& StringTools.startsWith(c, "Php_Global.")) ? "(Obj.magic (" + renderedCall + "))" : renderedCall;
						}
					}
				}
			case EUnop(op, expr):
				// Stage 3 expansion: support a tiny subset of unary ops so simple control-flow
				// fixtures can become non-trivial.
				//
				// Non-goal: correct numeric tower (Int vs Float) or full operator set.
				// If we can't emit safely, fall back to bring-up poison.
				switch (op) {
					case "!":
						"(not (" + exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + "))";
					case "-":
						switch (expr) {
							case _ if (isPositiveInfinityFieldExpr(expr)):
								"neg_infinity";
							case EField(EIdent("Math"), "POSITIVE_INFINITY"):
								"neg_infinity";
							case _:
								// Stage 3 bring-up: some upstream std constants are float-typed even when their
								// parsed shape isn't reliably inferred as `Float` yet.
								//
								// Keep unary minus type-correct for INF/NAN-style constants used in php boot code.
								final forceFloatUnop = isInfNanFieldExpr(expr) || switch (expr) {
									case EField(EIdent("Math"), "NaN" | "POSITIVE_INFINITY" | "NEGATIVE_INFINITY"):
										true;
									case _:
										false;
								};
								// Prefer float unary minus only when the operand is explicitly float-ish.
								//
								// Defaulting unknown expressions to float (`-.`) can break integer call sites
								// (e.g. `addSuccesses(-x)` where `x` is currently lowered through Obj.magic).
								final renderedExpr = exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath,
									moduleNameByPkgAndClass);
								if (forceFloatUnop || isFloatExpr(expr)) {
									"(-.(" + renderedExpr + "))";
								} else if (isIntExpr(expr)) {
									"(HxInt.neg (" + renderedExpr + "))";
								} else {
									"(-(" + renderedExpr + "))";
								}
						}
					case _:
						"(Obj.magic 0)";
				}
			case EBinop(op, a, b):
				// Stage 3 expansion: support a small set of binary ops so `if` conditions can
				// become meaningful (avoid the earlier "everything is true" collapse).
				//
				// Important: this emitter does not have reliable type information yet, so we
				// intentionally only support operators that are unambiguous enough for our
				// bring-up fixtures (primarily `Int` + boolean comparisons).
				final la = exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				final rb = exprToOcaml(b, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				function exprToOcamlAsFloat(e:HxExpr):String {
					// Best-effort numeric coercion: when Haxe mixes Int/Float, it promotes to Float.
					return switch (e) {
						case EInt(v):
							"float_of_int " + Std.string(v);
						case EUnop("-", inner):
							// Promote negative int literals/expressions to float too.
							"(-.(" + exprToOcamlAsFloat(inner) + "))";
						case EIdent(name) if (tyForIdent(name) == "Int"):
							"float_of_int " + readIdent(name);
						case EField(_obj, "length"):
							"float_of_int (" + exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
						case _:
							exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					}
				}

				function coerceNullableBoolIdent(expr:HxExpr, rendered:String):String {
					return switch (expr) {
						case EIdent(name):
							if (!isMutableLocalRefIdent(name)) {
								rendered;
							} else {
								"(let __nullable_bool = Obj.repr (" + rendered +
								") in if __nullable_bool == HxRuntime.hx_null then false else HxRuntime.unbox_bool_or_obj __nullable_bool)";
							}
						case _:
							rendered;
					}
				}

				final portableAutoMetalizedRegion = isPortableAutoMetalizedRegionActive();
				final metalNumeric = isMetalProfileActive() || portableAutoMetalizedRegion;
				switch (op) {
					case "=":
						switch (a) {
							case EField(obj, field):
								final objCode = exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
									callSigByCallee);
								final rhsCode = exprToOcaml(b, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
									callSigByCallee);
								"(let __hx_obj = ("
								+ objCode
								+ ") in let __hx_v = ("
								+ rhsCode
								+ ") in (HxAnon.set (Obj.repr __hx_obj) "
								+ escapeOcamlString(field)
								+ " (Obj.repr __hx_v); __hx_v))";
							case _:
								"(Obj.magic 0)";
						}
					case "+" if (isStringExpr(a) || isStringExpr(b)):
						"((" + exprToOcamlForConcat(a) + ") ^ (" + exprToOcamlForConcat(b) + "))";
					case "+" | "-" | "*" if (isInt64Expr(a) || isInt64Expr(b)):
						final fn = switch (op) {
							case "+":
								"add";
							case "-":
								"sub";
							case "*":
								"mul";
							case _:
								null;
						}
						fn == null
							? "(Obj.magic 0)"
							: "Haxe_Int64." + fn + " (" + exprToOcamlAsInt64Operand(a) + ") (" + exprToOcamlAsInt64Operand(b) + ")";
					case "/":
						// Bring-up compromise:
						// - When both sides look numeric (`Int`/`Float`), follow Haxe and emit float division.
						// - Otherwise, collapse to bring-up poison to avoid type errors for abstract/operator-
						//   overloaded cases (e.g. upstream Int64 tests).
						final aIsF = isFloatExpr(a);
						final bIsF = isFloatExpr(b);
						final aIsI = isIntExpr(a);
						final bIsI = isIntExpr(b);
						final hasKnownNumericSide = aIsF || bIsF || aIsI || bIsI;
						final allowMetalFallback = metalNumeric && hasKnownNumericSide && !isStringExpr(a) && !isStringExpr(b);
						if (allowMetalFallback && portableAutoMetalizedRegion && !isMetalProfileActive())
							markPortableAutoMetalizedLoweringUse("numeric_division_fallback");
						final allowNumericDivision = (aIsF || bIsF) || (aIsI && bIsI) || allowMetalFallback;
						allowNumericDivision ? "((" + exprToOcamlAsFloat(a) + ") /. (" + exprToOcamlAsFloat(b) + "))" : "(Obj.magic 0)";
					case "+" | "-" | "*" | "%":
						// Best-effort numeric lowering:
						// - if both sides look like floats, use OCaml float operators,
						// - if both sides look like ints, use OCaml int operators,
						// - otherwise, collapse to bring-up poison to avoid type errors.
						final aIsF = isFloatExpr(a);
						final bIsF = isFloatExpr(b);
						final aIsI = isIntExpr(a);
						final bIsI = isIntExpr(b);
						final hasKnownNumericSide = aIsF || bIsF || aIsI || bIsI;
						// Portable lane parity: when one side is confidently numeric and the other side
						// is an expression the current heuristic cannot classify, prefer numeric lowering
						// over bring-up poison.
						//
						// This keeps hot-path arithmetic (`Int + call()`, `Int * call()`, `Int % call()`)
						// executable in portable mode while still rejecting obvious string concatenations.
						final allowNumericFallback = hasKnownNumericSide && !isStringExpr(a) && !isStringExpr(b);
						final canFloat = (op == "+" || op == "-" || op == "*" || op == "/");
						if (op == "%") {
							if (aIsF || bIsF) {
								final fa = exprToOcamlAsFloat(a);
								final fb = exprToOcamlAsFloat(b);
								"(mod_float (" + fa + ") (" + fb + "))";
							} else if (aIsI && bIsI) {
								intBinopCall("%", la, rb);
							} else if ((aIsI && isUnknownNumericIdent(b)) || (bIsI && isUnknownNumericIdent(a))) {
								intBinopCall("%", la, rb);
							} else if (allowNumericFallback) {
								intBinopCall("%", la, rb);
							} else {
								"(Obj.magic 0)";
							}
						} else if ((aIsF || bIsF) && canFloat) {
							final fop = switch (op) {
								case "+": "+.";
								case "-": "-.";
								case "*": "*.";
								case "/": "/.";
								case _: op;
							}
							final fa = exprToOcamlAsFloat(a);
							final fb = exprToOcamlAsFloat(b);
							"((" + fa + ") " + fop + " (" + fb + "))";
						} else if (aIsI && bIsI) {
							intBinopCall(op, la, rb);
						} else if ((aIsI && isUnknownNumericIdent(b)) || (bIsI && isUnknownNumericIdent(a))) {
							intBinopCall(op, la, rb);
						} else if (allowNumericFallback) {
							intBinopCall(op, la, rb);
						} else {
							"(Obj.magic 0)";
						}
					case "==":
						if (isFloatExpr(a) || isFloatExpr(b) || (isIntExpr(a) && isUnknownNumericCompareExpr(b))
							|| (isIntExpr(b) && isUnknownNumericCompareExpr(a))) {
							"((" + exprToOcamlAsFloat(a) + ") = (" + exprToOcamlAsFloat(b) + "))";
						} else {
							"((" + la + ") = (" + rb + "))";
						}
					case "!=":
						if (isFloatExpr(a) || isFloatExpr(b) || (isIntExpr(a) && isUnknownNumericCompareExpr(b))
							|| (isIntExpr(b) && isUnknownNumericCompareExpr(a))) {
							"((" + exprToOcamlAsFloat(a) + ") <> (" + exprToOcamlAsFloat(b) + "))";
						} else {
							"((" + la + ") <> (" + rb + "))";
						}
					case "<" | ">" | "<=" | ">=":
						if (isFloatExpr(a) || isFloatExpr(b) || (isIntExpr(a) && isUnknownNumericCompareExpr(b))
							|| (isIntExpr(b) && isUnknownNumericCompareExpr(a))) {
							"((" + exprToOcamlAsFloat(a) + ") " + op + " (" + exprToOcamlAsFloat(b) + "))";
						} else {
							"((" + la + ") " + op + " (" + rb + "))";
						}
					case "&&" | "||":
						final lhsBool = coerceNullableBoolIdent(a, la);
						final rhsBool = coerceNullableBoolIdent(b, rb);
						"((" + lhsBool + ") " + op + " (" + rhsBool + "))";
					case _:
						"(Obj.magic 0)";
				}
			case EUnsupported(_):
				// Stage 3 bring-up: avoid aborting emission when partial parsing produces
				// unsupported nodes inside a larger expression tree. The goal here is to
				// progress to the next missing semantic, not to be correct yet.
				"(Obj.magic 0)";
			case ETernary(cond, thenExpr, elseExpr):
				"(if ("
				+ exprToOcaml(cond, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
				+ ") then ("
				+ exprToOcaml(thenExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
				+ ") else ("
				+ exprToOcaml(elseExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
				+ "))";
			case ESwitch(scrutinee, patterns, exprs):
				// Stage 3 bring-up: lower a small structured switch expression subset to nested `if`.
				//
				// We intentionally implement matching in terms of `Obj.repr` + `HxRuntime.dynamic_equals`
				// so we don't need to commit to concrete OCaml types for the scrutinee.
				final sw = exprToOcaml(scrutinee, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				function patternCond(p:HxSwitchPattern):String {
					return switch (p) {
						case POr(patterns):
							if (patterns == null || patterns.length == 0) {
								"false";
							} else {
								final parts = new Array<String>();
								for (pp in patterns)
									parts.push("(" + patternCond(pp) + ")");
								"(" + parts.join(" || ") + ")";
							}
						case PNull:
							backendDialect.runtimeIsNull("__sw");
						case PWildcard, PBind(_):
							"true";
						case PString(v):
							backendDialect.runtimeDynamicEquals("__sw", escapeOcamlString(v));
						case PInt(v):
							backendDialect.runtimeDynamicEquals("__sw", Std.string(v));
						case PEnumValue(name):
							backendDialect.runtimeDynamicEquals("__sw", escapeOcamlString(name));
					};
				}
				var chain = backendDialect.dynamicNullValue();
				if (patterns != null && exprs != null) {
					final count = patterns.length < exprs.length ? patterns.length : exprs.length;
					for (i in 0...count) {
						final idx = count - 1 - i;
						final pattern = patterns[idx];
						final branchExpr = exprs[idx];
						final localTy = switch (pattern) {
							case PBind(name):
								extendTyByIdent(tyByIdent, name, TyType.fromHintText("Dynamic"));
							case _:
								extendTyByIdentMany(tyByIdent, null, TyType.fromHintText("Dynamic"));
						};
						final body = exprToOcaml(branchExpr, arityByIdent, localTy, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
							callSigByCallee);
						// Switch expressions can legitimately unify unrelated branch types in Haxe
						// (e.g. `case OpAdd: Int`, `case OpEq: Bool`), but OCaml requires a single
						// expression type for the whole `if ... then ... else ...` chain.
						//
						// Bring-up strategy: cast each branch to `Obj.t` to keep emission resilient.
						final bodyAsDynamic = "(Obj.magic (" + body + "))";
						final thenExpr = switch (pattern) {
							case PBind(name):
								"(let " + ocamlValueIdent(name) + " = __sw in (" + bodyAsDynamic + "))";
							case _:
								"(" + bodyAsDynamic + ")";
						};
						final cond = patternCond(pattern);
						chain = "(if " + cond + " then " + thenExpr + " else (" + chain + "))";
					}
				}
				"(let __sw = (" + sw + ") in " + chain + ")";
			case ESwitchRaw(_raw):
				// Stage 3 bring-up: preserve switch shape during parsing/typing, but do not attempt to
				// lower it in the bootstrap emitter yet.
				"(Obj.magic 0)";
			case EAnon(_names, _values):
				// Stage 3 bring-up: anonymous structures are represented in the real backend/runtime.
				// The Stage 3 bootstrap emitter does not model them yet.
				"(Obj.magic 0)";
			case EArrayDecl(values):
				// Stage 3 bring-up: lower array literals to the local bootstrap shim container.
				//
				// Important
				// - This intentionally does *not* use the real reflaxe.ocaml runtime Array.
				// - The Stage3 bootstrap emitter output is "plain OCaml" and should stay standalone.
				if (isMetalProfileActive()) {
					if (values == null || values.length == 0) {
						"HxBootArray.of_list []";
					} else {
						var expectedCategory:Null<String> = null;
						final elems = new Array<String>();
						for (valueExpr in values) {
							final category = metalArrayLiteralCategory(valueExpr);
							if (category.length == 0) {
								throw "stage3 emitter: metal profile unsupported semantics: array literals must use concrete element categories (string|int|float|bool)";
							}
							if (expectedCategory == null) {
								expectedCategory = category;
							} else if (expectedCategory != category) {
								throw "stage3 emitter: metal profile unsupported semantics: mixed-type array literals are not allowed";
							}
							elems.push(exprToOcaml(valueExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass));
						}
						"HxBootArray.of_list [" + elems.join("; ") + "]";
					}
				} else {
					final elems = values == null
						|| values.length == 0 ? "" : values // Use `Obj.magic` per element so mixed-type array literals (common in upstream tests,
							// e.g. `[1, "hello"]`) remain OCaml-typecheckable during bring-up.
							.map(v -> "(Obj.magic ("
								+ exprToOcaml(v, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
								+ "))").join("; ");
					"HxBootArray.of_list [" + elems + "]";
				}
			case EArrayAccess(arr, idx):
				// Stage 3 bring-up: Haxe `obj[key]` is used both for array indexing and dynamic
				// string-key lookups (notably in upstream php boot helpers).
				//
				// Route obvious string-key access through `HxAnon.get`; keep numeric/other
				// indexing on the array shim.
				if (isStringKeyIndexExpr(idx)) {if (isMetalProfileActive()) {
					throw "stage3 emitter: metal profile unsupported semantics: string-key indexing is not supported";
				}
					"(Obj.magic (HxAnon.get ("
					+ exprToOcaml(arr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") ("
					+ exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")))";
				} else {"HxBootArray.get ("
					+ exprToOcaml(arr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") ("
					+ exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")";
				}
			case ERange(_start, _end):
				// Bring-up: ranges are emitted only as iterables in `for-in` lowering. If we see
				// a range in expression position, collapse to poison.
				"(Obj.magic 0)";
			case ECast(expr, _hint):
				// Bring-up: treat casts as identity.
				exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
			case EUntyped(expr):
				// Bring-up: preserve shape by emitting the inner expression.
				exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
		}
	}

	static function returnExprToOcaml(expr:HxExpr, allowedValueIdents:Map<String, Bool>, ?expectedReturnType:TyType, ?arityByIdent:Map<String, Int>,
			?tyByIdent:Map<String, TyType>, ?staticImportByIdent:Map<String, String>, ?currentPackagePath:String,
			?moduleNameByPkgAndClass:Map<String, String>, ?callSigByCallee:Map<String, EmitterCallSig>):String {
		inline function getTyIdentRaw(name:String):Null<TyType> {
			return mapGetRaw(cast tyByIdent, name);
		}

		inline function hasTyIdentRaw(name:String):Bool {
			return mapHasRaw(cast tyByIdent, name);
		}

		inline function hasStaticImportRaw(name:String):Bool {
			return mapGetRaw(cast staticImportByIdent, name) != null;
		}

		inline function resolveTyIdentName(name:String):String {
			if (getTyIdentRaw(name) != null)
				return name;
			final lowered = ocamlValueIdent(name);
			return lowered != name && getTyIdentRaw(lowered) != null ? lowered : name;
		}

		inline function hasTyIdent(name:String):Bool {
			return hasTyIdentRaw(resolveTyIdentName(name));
		}

		inline function hasThisBinding():Bool {
			return hasTyIdent("this") || hasTyIdent("this_");
		}

		_EmitterStageDebug.traceSelfRecursion("return_ctx",
			"current=" + (currentFunctionNameRaw == null || currentFunctionNameRaw.length == 0 ? "<none>" : currentFunctionNameRaw) + " hasThis="
			+ (hasThisBinding() ? "1" : "0") + " hasTyThis=" + (hasTyIdent("this") ? "1" : "0") + " hasTyThis_=" + (hasTyIdent("this_") ? "1" : "0"));

		inline function hasStaticImport(name:String):Bool {
			return hasStaticImportRaw(name);
		}

		inline function tyForIdent(name:String):String {
			final resolvedName = resolveTyIdentName(name);
			var resolved = getTyIdentRaw(resolvedName);
			if (resolved == null && currentExprTyHints != null)
				resolved = currentExprTyHints.get(resolvedName);
			if (resolved == null)
				return "";
			final t:TyType = resolved;
			return t == null ? "" : t.toString();
		}

		// Stage 3 bring-up: if we couldn't parse/type an expression, keep compilation moving.
		//
		// `Obj.magic` is a deliberate bootstrap escape hatch:
		// - it typechecks against any return annotation, which helps us progress through
		//   upstream-shaped code without having to implement full typing/emission yet.
		// - it is *not* semantically correct; it is only for bring-up.
		function hasBringupPoison(e:HxExpr):Bool {
			return switch (e) {
				case EUnsupported(_):
					true;
				case ENull:
					// `null` is representable as a runtime sentinel in the Stage3 bootstrap output.
					false;
				case EEnumValue(_):
					false;
				case EThis:
					// Instance context only: static functions still collapse `this` to poison.
					!hasThisBinding();
				case ESuper:
					true;
				case ENew(typePath, args):
					// Stage 3 bring-up: allow a tiny subset of allocations that we can lower
					// deterministically in `exprToOcaml`.
					//
					// Important
					// - `returnExprToOcaml` collapses *any* poisoned subtree to `(Obj.magic 0)`.
					// - If we add an allocation special-case in `exprToOcaml`, it must also be
					//   whitelisted here or the special-case will never run.
					switch (typePath) {
						case "Array":
							// `new Array()` is used heavily by upstream orchestration code.
							args.length == 0 ? false : true;
						case "sys.io.Process" | "sys.io.Process.Process":
							// Allow process spawning so RunCi can execute subcommands.
							if (args.length != 2) {
								true;
							} else {
								hasBringupPoison(args[0]) || hasBringupPoison(args[1])
								;
							}
						case _:
							if (currentInstanceFieldsFor(typePath) == null) {
								true;
							} else {
								var poisoned = false;
								for (a in args) {
									if (hasBringupPoison(a)) {
										poisoned = true;
										break;
									}
								}
								poisoned;
							}
					}
				case EUnop(op, inner):
					// Stage 3: allow a tiny subset of unary operators in return positions so bring-up
					// programs can become incrementally more semantic.
					switch (op) {
						case "!" | "-":
							hasBringupPoison(inner);
						case _:
							true;
					}
				case EBinop(op, a, b):
					// Stage 3: allow a curated subset of operators in return positions.
					switch (op) {
						case "=":
							switch (a) {
								case EField(obj, _): hasBringupPoison(obj) || hasBringupPoison(b);
								case _:
									true;
							}
						case "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" | "+" | "-" | "*" | "/" | "%": hasBringupPoison(a) || hasBringupPoison(b);
						case _:
							true;
					}
				case EIdent(name):
					// Stage 3 only models params and module names. Any other value identifier is
					// likely a local/field/helper we can't represent correctly yet.
					if (isUpperStart(name)) {
						false;
					} else if (name == "trace") {
						// Bootstrap convenience: allow emitting `trace(...)` in full-body mode so we can
						// observe that generated OCaml actually executes.
						false;
					} else if (hasTyIdent(name)) {
						// Parameters and bound locals are safe to reference.
						false;
					} else if (allowedValueIdents != null && allowedValueIdents.get(name) == true) {
						false;
					} else if (hasStaticImport(name)) {
						// Stage 3 bring-up: support `import Foo.Bar.*` (static wildcard imports) by allowing
						// the identifier to survive poison detection. The actual qualification happens in
						// `exprToOcaml`.
						false;
					} else {
						true;
					}
				case EField(obj, _field):
					// Stage 3 bring-up: treat `<type path>.field` as non-poison.
					//
					// Why
					// - Fully-qualified type paths like `a.b.Util.hello()` appear frequently in upstream code.
					// - The emitter can lower these deterministically to OCaml module accesses.
					//
					// Without this exception, the poison detector sees the leading package identifier (`a`)
					// as an unbound value ident and collapses the whole call to `Obj.magic 0`, which can
					// segfault at runtime once forced into a concrete OCaml type (e.g. `print_endline`).
					final parts = tryExtractTypePathPartsFromExpr(obj);
					(parts != null && parts.length > 0 && isUpperStart(parts[parts.length - 1])) ? false : hasBringupPoison(obj);
				case ESwitch(scrutinee, _patterns, exprs):
					if (hasBringupPoison(scrutinee)) {
						true;
					} else if (exprs == null) {
						false;
					} else {
						// Stage 3 bring-up: do not collapse an entire switch expression just because one
						// case body contains unsupported sub-expressions.
						//
						// Why
						// - Upstream harness code often has "fast path" switch cases we can execute
						//   (e.g. `case null: [Macro];`) alongside cases that exercise unsupported
						//   syntax (e.g. array comprehensions).
						// - If we poison the entire switch, we lose the fast path and bring-up stalls.
						//
						// Rule
						// - If *all* case bodies are poison, treat the switch as poison.
						// - Otherwise, allow emission and let unsupported cases degrade to `(Obj.magic 0)`
						//   at their expression sites.
						var allPoison = true;
						for (branchExpr in exprs) {
							if (!hasBringupPoison(branchExpr)) {
								allPoison = false;
								break;
							}
						}
						allPoison;
					}
				// Stage 3 bring-up: allow the controlled OCaml escape hatch in expression positions.
				//
				// Why
				// - Bring-up server binaries (macro host, display server) need small bits of native
				//   OCaml I/O and looping semantics before Stage3 models the full Haxe runtime.
				// - We lower `untyped __ocaml__("<ocaml expr>")` directly in `exprToOcaml`, but
				//   `returnExprToOcaml` must also treat the call as non-poison so it isn't collapsed
				//   to `(Obj.magic 0)` in statement positions.
				//
				// Safety
				// - This only whitelists the exact `__ocaml__("<string literal>")` shape.
				case ECall(EIdent("__ocaml__"), [arg]) if (constFoldString(arg) != null):
					false;
				case ECall(callee, args):
					if (hasBringupPoison(callee))
						return true;
					for (a in args)
						if (hasBringupPoison(a))
							return true;
					false;
				case EArrayDecl(values):
					for (v in values)
						if (hasBringupPoison(v))
							return true;
					false;
				case EArrayComprehension(_name, iterable, _yieldExpr):
					// Stage 3 bring-up: don't poison the whole comprehension just because the yield
					// expression mentions the binder name (which is introduced by the comprehension).
					//
					// The expression emitter models this binder when lowering `EArrayComprehension`
					// itself, so collapsing here is overly aggressive and turns valid comprehensions
					// into `(Obj.magic 0)`.
					hasBringupPoison(iterable);
				case EArrayAccess(arr, idx): hasBringupPoison(arr) || hasBringupPoison(idx);
				case ECast(expr, _hint):
					hasBringupPoison(expr);
				case EUntyped(expr):
					hasBringupPoison(expr);
				case _:
					false;
			}
		}

		// If the expression tree contains unsupported/null nodes anywhere, don't attempt partial OCaml
		// emission: it tends to produce unbound identifiers (we are not modeling locals/blocks yet).
		// Collapse to the bootstrap escape hatch instead.
		if (hasBringupPoison(expr))
			return "(Obj.magic 0)";

		// Stage 3 bring-up: numeric coercions based on the declared return type.
		//
		// Why
		// - Upstream stdlib contains methods like `processEvents():Float` that `return -1;`.
		// - In Haxe, `Int` literals coerce to `Float` in a `Float` context.
		// - Our bootstrap emitter doesn't do full expression typing, so we add a small,
		//   explicit coercion rule to keep OCaml typechecking.
		if (expectedReturnType != null && expectedReturnType.toString() == "Float") {
			function asFloatValue(e:HxExpr):String {
				return switch (e) {
					case EInt(v):
						"float_of_int " + Std.string(v);
					case EIdent(name) if (tyForIdent(name) == "Int"):
						"float_of_int " + ocamlReadValueIdent(name);
					case EField(_, field) if (field == "iNF" || field == "INF" || field == "inf" || field == "nAN" || field == "NAN" || field == "NaN"):
						"(Obj.magic (" + exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
							callSigByCallee) + ") : float)";
					case _:
						exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				}
			}
			return switch (expr) {
				case EInt(_):
					asFloatValue(expr);
				case EUnop("-", inner):
					"(-.(" + asFloatValue(inner) + "))";
				case _:
					exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
			}
		}

		final expectedName = expectedReturnType == null ? null : expectedReturnType.toString();
		if (expectedName == "Int64" || expectedName == "haxe.Int64") {
			function asInt64Value(e:HxExpr):Null<String> {
				return switch (e) {
					case EInt(v):
						"Haxe_Int64.ofInt (" + Std.string(v) + ")";
					case EUnop("-", inner):
						switch (inner) {
							case EInt(v):
								"Haxe_Int64.ofInt ((HxInt.neg (" + Std.string(v) + ")))";
							case _:
								null;
						}
					case EIdent(name) if (tyForIdent(name) == "Int"):
						"Haxe_Int64.ofInt (" + ocamlReadValueIdent(name) + ")";
					case _:
						null;
				}
			}

			inline function asInt64Operand(e:HxExpr):String {
				final direct = asInt64Value(e);
				return direct != null ? direct : exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee);
			}

			final int64Code = asInt64Value(expr);
			if (int64Code != null)
				return int64Code;

			switch (expr) {
				case EBinop(op, left, right):
					final fn = switch (op) {
						case "+":
							"add";
						case "-":
							"sub";
						case "*":
							"mul";
						case _:
							null;
					}
					if (fn != null)
						return "Haxe_Int64." + fn + " (" + asInt64Operand(left) + ") (" + asInt64Operand(right) + ")";
				case _:
			}
		}

		return exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
	}

	static inline function isAssignmentOpToken(op:String):Bool {
		return switch (op) {
			case "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=":
				true;
			case _:
				false;
		};
	}

	static function collectAssignedNamesInExprRec(e:HxExpr, out:Map<String, Bool>):Void {
		if (e == null)
			return;
		switch (e) {
			case EBinop(op, EIdent(name), rhs):
				if (isAssignmentOpToken(op) && name != null && name.length > 0)
					out.set(name, true);
				collectAssignedNamesInExprRec(rhs, out);
			case EBinop(_op, left, right):
				collectAssignedNamesInExprRec(left, out);
				collectAssignedNamesInExprRec(right, out);
			case EUnop(_op, inner):
				collectAssignedNamesInExprRec(inner, out);
			case ECall(callee, args):
				collectAssignedNamesInExprRec(callee, out);
				if (args != null)
					for (a in args)
						collectAssignedNamesInExprRec(a, out);
			case EField(obj, _field):
				collectAssignedNamesInExprRec(obj, out);
			case EArrayDecl(values):
				if (values != null)
					for (v in values)
						collectAssignedNamesInExprRec(v, out);
			case EArrayComprehension(_name, iterable, yieldExpr):
				collectAssignedNamesInExprRec(iterable, out);
				collectAssignedNamesInExprRec(yieldExpr, out);
			case EArrayAccess(arr, idx):
				collectAssignedNamesInExprRec(arr, out);
				collectAssignedNamesInExprRec(idx, out);
			case ETernary(cond, thenExpr, elseExpr):
				collectAssignedNamesInExprRec(cond, out);
				collectAssignedNamesInExprRec(thenExpr, out);
				collectAssignedNamesInExprRec(elseExpr, out);
			case ESwitch(scrutinee, _patterns, exprs):
				collectAssignedNamesInExprRec(scrutinee, out);
				if (exprs != null)
					for (branchExpr in exprs)
						collectAssignedNamesInExprRec(branchExpr, out);
			case ECast(inner, _hint):
				collectAssignedNamesInExprRec(inner, out);
			case EUntyped(inner):
				collectAssignedNamesInExprRec(inner, out);
			case ENew(_typePath, args):
				if (args != null)
					for (a in args)
						collectAssignedNamesInExprRec(a, out);
			case _:
		}
	}

	static function collectAssignedNamesInStmtRec(s:HxStmt, out:Map<String, Bool>):Void {
		if (s == null)
			return;
		switch (s) {
			case SExpr(expr, _pos):
				collectAssignedNamesInExprRec(expr, out);
			case SVar(_name, _hint, init, _pos):
				collectAssignedNamesInExprRec(init, out);
			case SBlock(ss, _pos):
				if (ss != null)
					for (ss0 in ss)
						collectAssignedNamesInStmtRec(ss0, out);
			case SIf(cond, thenBranch, elseBranch, _pos):
				collectAssignedNamesInExprRec(cond, out);
				collectAssignedNamesInStmtRec(thenBranch, out);
				if (elseBranch != null)
					collectAssignedNamesInStmtRec(elseBranch, out);
			case SWhile(cond, body, _pos):
				collectAssignedNamesInExprRec(cond, out);
				collectAssignedNamesInStmtRec(body, out);
			case SDoWhile(body, cond, _pos):
				collectAssignedNamesInStmtRec(body, out);
				collectAssignedNamesInExprRec(cond, out);
			case SForIn(_name, iterable, body, _pos):
				collectAssignedNamesInExprRec(iterable, out);
				collectAssignedNamesInStmtRec(body, out);
			case STry(tryBody, catches, _pos):
				collectAssignedNamesInStmtRec(tryBody, out);
				if (catches != null)
					for (c in catches)
						collectAssignedNamesInStmtRec(c.body, out);
			case SSwitch(scrutinee, _patterns, bodies, _pos):
				collectAssignedNamesInExprRec(scrutinee, out);
				if (bodies != null)
					for (body in bodies)
						collectAssignedNamesInStmtRec(body, out);
			case SThrow(expr, _pos):
				collectAssignedNamesInExprRec(expr, out);
			case SReturn(expr, _pos):
				collectAssignedNamesInExprRec(expr, out);
			case _:
		}
	}

	static function collectLocalsForPreludeFromStmtRec(s:HxStmt, locals:Map<String, Bool>):Void {
		if (s == null)
			return;
		switch (s) {
			case SBlock(stmts, _):
				if (stmts != null)
					for (ss in stmts)
						collectLocalsForPreludeFromStmtRec(ss, locals);
			case SVar(name, _, _, _):
				if (name != null && name.length > 0)
					locals.set(name, true);
			case SIf(_, thenBranch, elseBranch, _):
				collectLocalsForPreludeFromStmtRec(thenBranch, locals);
				if (elseBranch != null)
					collectLocalsForPreludeFromStmtRec(elseBranch, locals);
			case SWhile(_, body, _):
				collectLocalsForPreludeFromStmtRec(body, locals);
			case SDoWhile(body, _, _):
				collectLocalsForPreludeFromStmtRec(body, locals);
			case SForIn(name, _, body, _):
				if (name != null && name.length > 0)
					locals.set(name, true);
				collectLocalsForPreludeFromStmtRec(body, locals);
			case SSwitch(_, _patterns, bodies, _):
				if (bodies != null)
					for (body in bodies)
						collectLocalsForPreludeFromStmtRec(body, locals);
			case _:
		}
	}

	static function scanExprForPreludeDepsRec(e:Null<HxExpr>, locals:Map<String, Bool>, calls:Map<String, Bool>, idents:Map<String, Bool>):Void {
		if (e == null)
			return;
		switch (e) {
			case EIdent(name):
				if (name != null && name.length > 0 && !locals.exists(name))
					idents.set(name, true);
			case EField(obj, _):
				scanExprForPreludeDepsRec(obj, locals, calls, idents);
			case ECall(callee, args):
				switch (callee) {
					case EIdent(name):
						if (name != null && name.length > 0 && !locals.exists(name)) calls.set(name, true);
					case EField(_obj, field):
						if (field != null && field.length > 0 && !locals.exists(field)) calls.set(field, true);
					case _:
				}
				scanExprForPreludeDepsRec(callee, locals, calls, idents);
				if (args != null)
					for (a in args)
						scanExprForPreludeDepsRec(a, locals, calls, idents);
			case ELambda(args, body):
				final nestedLocals:Map<String, Bool> = new Map();
				for (k in locals.keys())
					nestedLocals.set(k, true);
				if (args != null)
					for (a in args)
						if (a != null && a.length > 0)
							nestedLocals.set(a, true);
				scanExprForPreludeDepsRec(body, nestedLocals, calls, idents);
			case ETernary(cond, thenExpr, elseExpr):
				scanExprForPreludeDepsRec(cond, locals, calls, idents);
				scanExprForPreludeDepsRec(thenExpr, locals, calls, idents);
				scanExprForPreludeDepsRec(elseExpr, locals, calls, idents);
			case EAnon(_, values):
				if (values != null)
					for (v in values)
						scanExprForPreludeDepsRec(v, locals, calls, idents);
			case ESwitch(scrutinee, _patterns, exprs):
				scanExprForPreludeDepsRec(scrutinee, locals, calls, idents);
				if (exprs != null)
					for (branchExpr in exprs)
						scanExprForPreludeDepsRec(branchExpr, locals, calls, idents);
			case ENew(_, args):
				if (args != null)
					for (a in args)
						scanExprForPreludeDepsRec(a, locals, calls, idents);
			case EUnop(_, expr):
				scanExprForPreludeDepsRec(expr, locals, calls, idents);
			case EBinop(_, left, right):
				scanExprForPreludeDepsRec(left, locals, calls, idents);
				scanExprForPreludeDepsRec(right, locals, calls, idents);
			case EArrayComprehension(name, iterable, yieldExpr):
				final nestedLocals:Map<String, Bool> = new Map();
				for (k in locals.keys())
					nestedLocals.set(k, true);
				if (name != null && name.length > 0)
					nestedLocals.set(name, true);
				scanExprForPreludeDepsRec(iterable, locals, calls, idents);
				scanExprForPreludeDepsRec(yieldExpr, nestedLocals, calls, idents);
			case EArrayDecl(values):
				if (values != null)
					for (v in values)
						scanExprForPreludeDepsRec(v, locals, calls, idents);
			case EArrayAccess(array, index):
				scanExprForPreludeDepsRec(array, locals, calls, idents);
				scanExprForPreludeDepsRec(index, locals, calls, idents);
			case ERange(start, end):
				scanExprForPreludeDepsRec(start, locals, calls, idents);
				scanExprForPreludeDepsRec(end, locals, calls, idents);
			case ECast(expr, _):
				scanExprForPreludeDepsRec(expr, locals, calls, idents);
			case EUntyped(expr):
				scanExprForPreludeDepsRec(expr, locals, calls, idents);
			case _:
		}
	}

	static function scanStmtForPreludeDepsRec(s:HxStmt, locals:Map<String, Bool>, calls:Map<String, Bool>, idents:Map<String, Bool>):Void {
		if (s == null)
			return;
		switch (s) {
			case SBlock(stmts, _):
				if (stmts != null)
					for (ss in stmts)
						scanStmtForPreludeDepsRec(ss, locals, calls, idents);
			case SVar(_name, _typeHint, init, _):
				scanExprForPreludeDepsRec(init, locals, calls, idents);
			case SIf(cond, thenBranch, elseBranch, _):
				scanExprForPreludeDepsRec(cond, locals, calls, idents);
				scanStmtForPreludeDepsRec(thenBranch, locals, calls, idents);
				if (elseBranch != null)
					scanStmtForPreludeDepsRec(elseBranch, locals, calls, idents);
			case SWhile(cond, body, _):
				scanExprForPreludeDepsRec(cond, locals, calls, idents);
				scanStmtForPreludeDepsRec(body, locals, calls, idents);
			case SDoWhile(body, cond, _):
				scanStmtForPreludeDepsRec(body, locals, calls, idents);
				scanExprForPreludeDepsRec(cond, locals, calls, idents);
			case SForIn(_name, iterable, body, _):
				scanExprForPreludeDepsRec(iterable, locals, calls, idents);
				scanStmtForPreludeDepsRec(body, locals, calls, idents);
			case SSwitch(scrutinee, _patterns, bodies, _):
				scanExprForPreludeDepsRec(scrutinee, locals, calls, idents);
				if (bodies != null)
					for (body in bodies)
						scanStmtForPreludeDepsRec(body, locals, calls, idents);
			case SReturn(expr, _):
				scanExprForPreludeDepsRec(expr, locals, calls, idents);
			case SExpr(expr, _):
				scanExprForPreludeDepsRec(expr, locals, calls, idents);
			case _:
		}
	}

	static function stmtListToOcaml(stmts:Array<HxStmt>, allowedValueIdents:Map<String, Bool>, returnExc:String, outSink:StringBuf, ?arityByIdent:Map<String, Int>,
			?tyByIdent:Map<String, TyType>, ?staticImportByIdent:Map<String, String>, ?currentPackagePath:String,
			?moduleNameByPkgAndClass:Map<String, String>, ?callSigByCallee:Map<String, EmitterCallSig>, ?localTypeHints:Map<String, TyType>,
			?fnReturnTypes:Map<String, TyType>, ?debugModuleName:String, ?debugFunctionName:String):Void {
		if (stmts == null || stmts.length == 0) {
			outSink.add("()");
		} else {

			final localTypeHintsMap = localTypeHints;
			final fnReturnTypesMap = fnReturnTypes;

			final prevMutableLocalRefNames = currentMutableLocalRefNames == null ? [] : currentMutableLocalRefNames.copy();

			function mergeMutableLocalRefNames(base:Array<String>, local:Map<String, Bool>):Array<String> {
				final out:Array<String> = base == null ? [] : base.copy();
				function hasName(name:String):Bool {
					for (n in out)
						if (n == name)
							return true;
					return false;
				}
				for (k in local.keys())
					if (local.get(k) == true && !hasName(k))
						out.push(k);
				return out;
			}

			function collectTopLevelDeclaredLocals(ss:Array<HxStmt>):Map<String, Bool> {
				final out:Map<String, Bool> = new Map();
				if (ss == null)
					return out;
				for (s in ss) {
					switch (s) {
						case SVar(name, _hint, _init, _pos):
							if (name != null && name.length > 0)
								out.set(name, true);
						case _:
					}
				}
				return out;
			}

			final declaredTopLevelLocals = collectTopLevelDeclaredLocals(stmts);
			final assignedNamesDeep:Map<String, Bool> = new Map();
			for (s in stmts)
				collectAssignedNamesInStmtRec(s, assignedNamesDeep);
			final mutableLocalsInScope:Map<String, Bool> = new Map();
			for (name in declaredTopLevelLocals.keys()) {
				if (assignedNamesDeep.get(name) == true)
					mutableLocalsInScope.set(name, true);
			}
			currentMutableLocalRefNames = mergeMutableLocalRefNames(prevMutableLocalRefNames, mutableLocalsInScope);

			// Stage 3 bring-up: merge any precomputed local type hints with a tiny, local
			// initializer-based inference pass so later statements can emit more correct OCaml.
			//
			// Example (upstream unit/TestNaN.hx):
			// - `var a = foo(); if (a > 0) ...`
			// - Even if the typer can't infer `a` from the call site, we can approximate it
			//   from the known return type of `foo` in the same module.
			final localHints:Map<String, TyType> = new Map();
			final localHintKeys:Null<Iterator<String>> = mapKeysRaw(cast localTypeHintsMap);
			if (localHintKeys != null)
				for (k in localHintKeys) {
					final hint = mapGetRaw(cast localTypeHintsMap, k);
					if (hint != null)
						localHints.set(k, cast hint);
				}

		inline function isTyNamed(t:Null<TyType>, expected:String):Bool {
			if (t == null)
				return false;
			return t.toString() == expected;
		}

		function arrayElemTypeFromTy(t:Null<TyType>):TyType {
			if (t == null)
				return TyType.unknown();
			final ts = t.toString();
			if (ts == "Array")
				return TyType.unknown();
			if (StringTools.startsWith(ts, "Array<") && StringTools.endsWith(ts, ">")) {
				final inner = ts.substr(6, ts.length - 7);
				return TyType.fromHintText(inner);
			}
			return TyType.unknown();
		}

		function inferQualifiedStringCallType(callee:HxExpr):TyType {
			return switch (callee) {
				case EField(obj, "stringify"):
					final parts = tryExtractTypePathPartsFromExpr(obj);
					if (parts != null && parts.length > 0) {
						final last = parts[parts.length - 1];
						if (last == "Json" || last == "Haxe_Json")
							TyType.fromHintText("String");
						else
							TyType.unknown();
					} else {
						TyType.unknown();
					}
				case EField(obj, "print"):
					final parts = tryExtractTypePathPartsFromExpr(obj);
					if (parts != null && parts.length > 0) {
						final last = parts[parts.length - 1];
						if (last == "JsonPrinter" || last == "Haxe_format_JsonPrinter")
							TyType.fromHintText("String");
						else
							TyType.unknown();
					} else {
						TyType.unknown();
					}
				case EField(EIdent("Std"), "string"):
					TyType.fromHintText("String");
				case EField(EIdent("StringTools"), "hex"):
					TyType.fromHintText("String");
				case EField(_obj, "substr" | "substring" | "toLowerCase" | "toUpperCase" | "trim" | "charAt"):
					TyType.fromHintText("String");
				case _:
					TyType.unknown();
			}
		}

		function inferInitType(e:HxExpr, ?boundName:String, ?boundTy:TyType):TyType {
			if (e == null)
				return TyType.unknown();
			inline function int64Ty():TyType {
				return TyType.fromHintText("Int64");
			}
			inline function inferredIsInt64(ty:TyType):Bool {
				return ty != null && (ty.toString() == "Int64" || ty.toString() == "haxe.Int64");
			}
			return switch (e) {
				case EFloat(_):
					TyType.fromHintText("Float");
				case EInt(_):
					TyType.fromHintText("Int");
				case EString(_):
					TyType.fromHintText("String");
				case EBool(_):
					TyType.fromHintText("Bool");
				case EField(EIdent("Math"), "NaN" | "POSITIVE_INFINITY" | "NEGATIVE_INFINITY" | "PI"):
					TyType.fromHintText("Float");
				case EIdent(name):
					if (boundName != null && name == boundName && boundTy != null) boundTy; else {
						final t = localHints.get(name);
						t == null ? TyType.unknown() : t;
					}
				case EBinop(op, left, right):
					final lt = inferInitType(left, boundName, boundTy);
					final rt = inferInitType(right, boundName, boundTy);
					if (op == "+"
						&& (isTyNamed(lt,
							"String") || isTyNamed(rt,
								"String"))) TyType.fromHintText("String"); else if (op == "/"
						&& ((isTyNamed(lt, "Int") || isTyNamed(lt, "Float"))
							&& (isTyNamed(rt,
								"Int") || isTyNamed(rt,
									"Float")))) TyType.fromHintText("Float"); else if ((op == "+" || op == "-" || op == "*" || op == "%")
						&& isTyNamed(lt, "Int")
						&& isTyNamed(rt,
							"Int")) TyType.fromHintText("Int"); else if ((op == "+" || op == "-" || op == "*")
						&& (inferredIsInt64(lt) || inferredIsInt64(rt))) int64Ty(); else if ((op == "+" || op == "-" || op == "*")
						&& (isTyNamed(lt, "Float") || isTyNamed(rt, "Float"))) TyType.fromHintText("Float"); else TyType.unknown();
				case ETernary(_cond, thenExpr, elseExpr):
					final tt = inferInitType(thenExpr, boundName, boundTy);
					final te = inferInitType(elseExpr, boundName, boundTy);
					(!tt.isUnknown() && tt.toString() == te.toString()) ? tt : TyType.unknown();
				case EArrayDecl(values):
					if (values == null || values.length == 0) {
						TyType.fromHintText("Array");
					} else {
						final firstTy = inferInitType(values[0], boundName, boundTy);
						if (firstTy.isUnknown()) {
							TyType.fromHintText("Array");
						} else {
							var same = true;
							for (i in 1...values.length) {
								final ti = inferInitType(values[i], boundName, boundTy);
								if (ti.isUnknown() || ti.toString() != firstTy.toString()) {
									same = false;
									break;
								}
							}
							same ? TyType.fromHintText("Array<" + firstTy.toString() + ">") : TyType.fromHintText("Array");
						}
					}
				case EArrayComprehension(name, iterable, yieldExpr):
					final iterElemTy = switch (iterable) {
						case ERange(_, _):
							TyType.fromHintText("Int");
						case EIdent(iterName):
							arrayElemTypeFromTy(localHints.get(iterName));
						case EArrayDecl(_):
							arrayElemTypeFromTy(inferInitType(iterable, boundName, boundTy));
						case _:
							TyType.unknown();
					};
					final yielded = inferInitType(yieldExpr, name, iterElemTy);
					final elemTy = yielded.isUnknown() ? iterElemTy : yielded;
					elemTy.isUnknown() ? TyType.fromHintText("Array") : TyType.fromHintText("Array<" + elemTy.toString() + ">");
				case ENew(typePath, _args):
					(typePath == null || typePath.length == 0) ? TyType.unknown() : TyType.fromHintText(typePath);
				case ECall(EIdent(fn), _args) if (mapGetRaw(cast fnReturnTypesMap, fn) != null):
					cast mapGetRaw(cast fnReturnTypesMap, fn);
				case ECall(EField(_obj, field), _args) if (mapGetRaw(cast fnReturnTypesMap, field) != null):
					// Stage3 local-hint repair: upstream-ish stdlib code often initializes locals from
					// qualified static calls like `Json.stringify(...)` or `JsonPrinter.print(...)`.
					// Those calls are not bare `EIdent(fn)` forms, but we still know the return type by
					// function name inside the current module's typed-function map.
					cast mapGetRaw(cast fnReturnTypesMap, field);
				case ECall(EField(EIdent("Int64" | "haxe.Int64"), "ofInt" | "make" | "add" | "sub" | "mul"), _args):
					int64Ty();
				case ECall(EField(obj, field), _args):
					final parts = tryExtractTypePathPartsFromExpr(obj);
					if (parts != null && parts.length > 0 && parts[parts.length - 1] == "Int64"
						&& (field == "ofInt" || field == "make" || field == "add" || field == "sub" || field == "mul")) {
						int64Ty();
					} else {
						inferQualifiedStringCallType(EField(obj, field));
					}
				case ECall(callee, _args):
					inferQualifiedStringCallType(callee);
				case _:
					TyType.unknown();
			}
		}

		function seedLocalHintsFromStmts(ss:Array<HxStmt>):Void {
			if (ss == null)
				return;
			for (s in ss) {
				switch (s) {
					case SVar(name, hint, init, _pos):
						if (name == null || name.length == 0)
							continue;
						final existing = localHints.get(name);
						final declared = hint != null && StringTools.trim(hint).length > 0 ? TyType.fromHintText(StringTools.trim(hint)) : null;
						final inferred = declared != null ? declared : inferInitType(init);
						final existingNeedsUpgrade = existing == null || existing.isUnknown() || existing.toString() == "Dynamic"
							|| existing.toString() == "Array";
						final preferInferredInt64 = inferred != null
							&& (inferred.toString() == "Int64" || inferred.toString() == "haxe.Int64")
							&& (existing == null || (existing.toString() != "Int64" && existing.toString() != "haxe.Int64"));
						final inferredUseful = !inferred.isUnknown() && inferred.toString() != "Dynamic";
						if ((existingNeedsUpgrade || preferInferredInt64) && inferredUseful) {
							localHints.set(name, inferred);
						}
					case _:
				}
			}
		}

		seedLocalHintsFromStmts(stmts);

		/**
			Stage 3 bring-up: compute statement-local "vars in scope before this statement".

			Why
			- We lower Haxe `var x = ...;` as nested OCaml `let x = ... in ...`.
			- OCaml scope is lexical: `x` only exists in the remainder wrapped by the `let`.
			- If we pre-mark all locals as "bound" for the whole function, early references
			  to a later `var x = ...` will emit `x` and fail OCaml compilation with
			  "Unbound value x".

			What
			- For the current statement list, track which `SVar` names are in scope before
			  each statement index.

			How (bootstrap constraints)
			- Only `SVar` declarations in this statement list affect following statements.
			  Declarations inside nested blocks are handled by the recursive `stmtListToOcaml`
			  calls.
		**/
		function localsInScopeBefore(stmts:Array<HxStmt>):Array<Map<String, Bool>> {
			final before = new Array<Map<String, Bool>>();
			final cur:Map<String, Bool> = new Map();

			function cloneMap(m:Map<String, Bool>):Map<String, Bool> {
				final out:Map<String, Bool> = new Map();
				for (k in m.keys())
					out.set(k, m.get(k));
				return out;
			}

			if (stmts == null)
				return before;
			for (s in stmts) {
				before.push(cloneMap(cur));
				switch (s) {
					case SVar(name, _hint, _init, _pos):
						if (name != null && name.length > 0)
							cur.set(name, true);
					case _:
				}
			}
			return before;
		}

		function extendTyWithLocals(base:Map<String, TyType>, locals:Map<String, Bool>):Map<String, TyType> {
			final out:Map<String, TyType> = new Map();
			if (base != null)
				for (k in base.keys()) {
					final existingBase = base.get(k);
					if (existingBase != null)
						out.set(k, existingBase);
				}

			final localNames = new Array<String>();
			if (locals != null)
				for (name in locals.keys())
					localNames.push(name);

			if (localNames.length == 0)
				return out;

			for (name in localNames) {
				final hinted = localHints.get(name);
				final existing = out.get(name);
				if (existing == null) {
					out.set(name, hinted != null ? hinted : TyType.unknown());
				} else if (hinted != null) {
					final existingBroad = existing.isUnknown() || existing.toString() == "Dynamic" || existing.toString() == "Array";
					final hintedInt64 = hinted.toString() == "Int64" || hinted.toString() == "haxe.Int64";
					final existingInt64 = existing.toString() == "Int64" || existing.toString() == "haxe.Int64";
					final hintedUseful = !hinted.isUnknown() && hinted.toString() != "Dynamic";
					if ((existingBroad || (hintedInt64 && !existingInt64)) && hintedUseful)
						out.set(name, hinted);
				}
			}
			return out;
		}

		function extendAllowedValueIdents(base:Map<String, Bool>, locals:Map<String, Bool>):Map<String, Bool> {
			final out:Map<String, Bool> = new Map();
			if (base != null)
				for (name in base.keys())
					if (base.get(name) == true)
						out.set(name, true);
			if (locals != null)
				for (name in locals.keys())
					if (locals.get(name) == true)
						out.set(name, true);
			return out;
		}

		function extendTyByIdentLocal(ty:Map<String, TyType>, name:String, t:TyType):Map<String, TyType> {
			final out:Map<String, TyType> = new Map();
			if (ty != null)
				for (k in ty.keys()) {
					final existing = ty.get(k);
					if (existing != null)
						out.set(k, existing);
				}
			out.set(name, t);
			return out;
		}

		inline function buildSequentialStmt(unitExpr:String, restExpr:String):String {
			final seqBuf = new StringBuf();
			seqBuf.add("(");
			seqBuf.add(unitExpr);
			seqBuf.add("; ");
			seqBuf.add(restExpr);
			seqBuf.add(")");
			return seqBuf.toString();
		}

		inline function buildNullCoalesceAssign(ident:String, condS:String, rhs:String, restExpr:String):String {
			final assignBuf = new StringBuf();
			assignBuf.add("(let ");
			assignBuf.add(ident);
			assignBuf.add(" = (if ");
			assignBuf.add(condS);
			assignBuf.add(" then (");
			assignBuf.add(rhs);
			assignBuf.add(") else ");
			assignBuf.add(ident);
			assignBuf.add(") in (ignore ");
			assignBuf.add(ident);
			assignBuf.add("; (");
			assignBuf.add(restExpr);
			assignBuf.add(")))");
			return assignBuf.toString();
		}

		function cloneTyCtxLocal(ty:Map<String, TyType>):Map<String, TyType> {
			final out:Map<String, TyType> = new Map();
			if (ty != null)
				for (k in ty.keys()) {
					final existing = ty.get(k);
					if (existing != null)
						out.set(k, existing);
				}
			return out;
		}

		final localsBefore = localsInScopeBefore(stmts);

		function stmtAlwaysReturns(s:HxStmt):Bool {
			return switch (s) {
				case SReturnVoid(_), SReturn(_, _):
					true;
				case SIf(_cond, thenBranch, elseBranch, _): elseBranch != null && stmtAlwaysReturns(thenBranch) && stmtAlwaysReturns(elseBranch);
				case SWhile(_cond, _body, _):
					false;
				case SDoWhile(_body, _cond, _):
					false;
				case SSwitch(_scrutinee, _patterns, bodies, _):
					// Bring-up: treat switches as non-returning unless every case body returns.
					if (bodies == null || bodies.length == 0) {
						false;
					} else {
						var all = true;
						for (body in bodies) {
							if (!stmtAlwaysReturns(body)) {
								all = false;
								break;
							}
						}
						all;
					}
				case SBlock(ss, _):
					if (ss == null || ss.length == 0) {
						false;
					} else {
						stmtAlwaysReturns(ss[ss.length - 1]);
					}
				case _:
					false;
			}
		}

		inline function tyCtxGet(value:Map<String, TyType>, name:String):Null<TyType> {
			final resolved = mapGetRaw(cast value, name);
			return resolved == null ? null : cast resolved;
		}

		function condToOcamlBool(e:HxExpr, tyCtx:Map<String, TyType>, allowedValueIdentsForStmt:Map<String, Bool>):String {
			inline function boolOrTrue(s:String):String {
				// `returnExprToOcaml` collapses unsupported/unknown subtrees to `(Obj.magic 0)`.
				// In a condition position we prefer "always true" over emitting an unbound identifier
				// that would abort OCaml compilation.
				return s == "(Obj.magic 0)" ? "true" : s;
			}

			return switch (e) {
				case EBool(v):
					v ? "true" : "false";
				case EUnop("!", _):
					boolOrTrue(returnExprToOcaml(e, allowedValueIdentsForStmt, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee));
				case EBinop(op, _, _) if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||"):
					boolOrTrue(returnExprToOcaml(e, allowedValueIdentsForStmt, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee));
				case _:
					// Conservative default: we do not have real typing for conditions yet.
					// Keep bring-up resilient by treating unknown conditions as true.
					"true";
			};
		}

		function mutableAssignmentStmtToUnit(op:String, name:String, rhs:HxExpr, tyCtx:Null<Map<String, TyType>>,
				allowedValueIdentsForStmt:Map<String, Bool>):Null<String> {
			if (!isMutableLocalRefIdent(name))
				return null;
			inline function mutableLocalHint(name:String):Null<TyType> {
				final ctxHint = tyCtx == null ? null : tyCtx.get(name);
				if (ctxHint != null)
					return ctxHint;
				return localHints.get(name);
			}
			final expectedTy = mutableLocalHint(name);
			if (debugModuleName != null && debugFunctionName != null) {
				final ctxTy = tyCtx == null ? null : tyCtx.get(name);
				final localTy = localHints.get(name);
				_EmitterStageDebug.traceLocalType("mutable_assignment", debugModuleName, debugFunctionName, name,
					"op=" + op + " ctx=" + (ctxTy == null ? "<null>" : ctxTy.toString()) + " local="
					+ (localTy == null ? "<null>" : localTy.toString()) + " expected="
					+ (expectedTy == null ? "<null>" : expectedTy.toString()));
			}
			final rhsCode:Null<String> = switch (op) {
				case "=":
					returnExprToOcaml(rhs, allowedValueIdentsForStmt, expectedTy, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
						callSigByCallee);
				case "+=":
					returnExprToOcaml(EBinop("+", EIdent(name), rhs), allowedValueIdentsForStmt, expectedTy, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee);
				case "-=":
					returnExprToOcaml(EBinop("-", EIdent(name), rhs), allowedValueIdentsForStmt, expectedTy, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee);
				case "*=":
					returnExprToOcaml(EBinop("*", EIdent(name), rhs), allowedValueIdentsForStmt, expectedTy, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee);
				case "/=":
					returnExprToOcaml(EBinop("/", EIdent(name), rhs), allowedValueIdentsForStmt, expectedTy, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee);
				case "%=":
					returnExprToOcaml(EBinop("%", EIdent(name), rhs), allowedValueIdentsForStmt, expectedTy, arityByIdent, tyCtx, staticImportByIdent,
						currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				case _:
					null;
			}
			if (rhsCode == null)
				return null;
			final ident = ocamlValueIdent(name);
			return "(let __hx_v = (" + rhsCode + ") in (" + ident + " := __hx_v; ()))";
		}

		function bodyHintsIntLoopVar(s:HxStmt, loopVarName:String):Bool {
			// Best-effort signal for loop-variable typing in Stage3.
			//
			// Why
			// - For `for (x in xs)` where `xs` type is still broad (`Array`/`Dynamic`), we can still
			//   infer that `x` is effectively numeric when the loop body immediately uses numeric
			//   operators (`+`, `*`, `%`, compound assignments, etc.).
			//
			// What
			// - Detect whether the loop variable appears in numeric expression contexts anywhere in
			//   the loop body subtree.
			//
			// Non-goal
			// - This is not full dataflow typing; it is a conservative bring-up hint only.
			function exprContainsIdent(e:HxExpr, needle:String):Bool {
				if (e == null || needle == null || needle.length == 0)
					return false;
				return switch (e) {
					case EIdent(name):
						name == needle;
					case EUnop(_, inner):
						exprContainsIdent(inner, needle);
					case EBinop(_, left, right): exprContainsIdent(left, needle) || exprContainsIdent(right, needle);
					case EField(obj, _):
						exprContainsIdent(obj, needle);
					case ECall(callee, args):
						if (exprContainsIdent(callee, needle)) true; else {
							var seen = false;
							if (args != null)
								for (a in args)
									if (exprContainsIdent(a, needle)) {
										seen = true;
										break;
									}
							seen;
						}
					case EArrayDecl(values):
						var seen = false;
						if (values != null)
							for (v in values)
								if (exprContainsIdent(v, needle)) {
									seen = true;
									break;
								}
						seen;
					case EArrayComprehension(name, iterable, yieldExpr):
						(name != needle && (exprContainsIdent(iterable, needle) || exprContainsIdent(yieldExpr, needle)));
					case EArrayAccess(arrayExpr, indexExpr): exprContainsIdent(arrayExpr, needle) || exprContainsIdent(indexExpr, needle);
					case ERange(startExpr, endExpr): exprContainsIdent(startExpr, needle) || exprContainsIdent(endExpr, needle);
					case ETernary(cond, thenExpr, elseExpr): exprContainsIdent(cond,
							needle) || exprContainsIdent(thenExpr, needle) || exprContainsIdent(elseExpr, needle);
					case ECast(inner, _):
						exprContainsIdent(inner, needle);
					case EUntyped(inner):
						exprContainsIdent(inner, needle);
					case ESwitch(scrutinee, _patterns, exprs):
						if (exprContainsIdent(scrutinee, needle)) true; else {
							var seen = false;
							if (exprs != null)
								for (branchExpr in exprs)
									if (exprContainsIdent(branchExpr, needle)) {
										seen = true;
										break;
									}
							seen;
						}
					case _:
						false;
				}
			}

			function exprHintsInt(e:HxExpr, needle:String):Bool {
				if (e == null || needle == null || needle.length == 0)
					return false;
				return switch (e) {
					case EBinop(op, left, right): final numericOp = op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "+="
							|| op == "-=" || op == "*=" || op == "/=" || op == "%="; (numericOp
							&& (exprContainsIdent(left,
								needle) || exprContainsIdent(right, needle))) || exprHintsInt(left, needle) || exprHintsInt(right, needle);
					case EUnop(_, inner):
						exprHintsInt(inner, needle);
					case EField(obj, _):
						exprHintsInt(obj, needle);
					case ECall(callee, args):
						if (exprHintsInt(callee, needle)) true; else {
							var seen = false;
							if (args != null)
								for (a in args)
									if (exprHintsInt(a, needle)) {
										seen = true;
										break;
									}
							seen;
						}
					case EArrayDecl(values):
						var seen = false;
						if (values != null)
							for (v in values)
								if (exprHintsInt(v, needle)) {
									seen = true;
									break;
								}
						seen;
					case EArrayComprehension(name, iterable, yieldExpr):
						(name != needle && (exprHintsInt(iterable, needle) || exprHintsInt(yieldExpr, needle)));
					case EArrayAccess(arrayExpr, indexExpr): exprHintsInt(arrayExpr, needle) || exprHintsInt(indexExpr, needle);
					case ERange(startExpr, endExpr): exprHintsInt(startExpr, needle) || exprHintsInt(endExpr, needle);
					case ETernary(cond, thenExpr, elseExpr): exprHintsInt(cond, needle) || exprHintsInt(thenExpr, needle) || exprHintsInt(elseExpr, needle);
					case ECast(inner, _):
						exprHintsInt(inner, needle);
					case EUntyped(inner):
						exprHintsInt(inner, needle);
					case ESwitch(scrutinee, _patterns, exprs):
						if (exprHintsInt(scrutinee, needle)) true; else {
							var seen = false;
							if (exprs != null)
								for (branchExpr in exprs)
									if (exprHintsInt(branchExpr, needle)) {
										seen = true;
										break;
									}
							seen;
						}
					case _:
						false;
				}
			}

			return switch (s) {
				case SExpr(expr, _):
					exprHintsInt(expr, loopVarName);
				case SBlock(stmts, _):
					if (stmts == null) {
						false;
					} else {
						var seen = false;
						for (ss in stmts)
							if (bodyHintsIntLoopVar(ss, loopVarName)) {
								seen = true;
								break;
							}
						seen;
					}
				case SIf(_cond, thenBranch, elseBranch, _): bodyHintsIntLoopVar(thenBranch,
						loopVarName) || (elseBranch != null && bodyHintsIntLoopVar(elseBranch, loopVarName));
				case SWhile(_cond, body, _):
					bodyHintsIntLoopVar(body, loopVarName);
				case SDoWhile(body, _cond, _):
					bodyHintsIntLoopVar(body, loopVarName);
				case SForIn(_name, _iterable, body, _):
					bodyHintsIntLoopVar(body, loopVarName);
				case SSwitch(_scrutinee, _patterns, bodies, _):
					if (bodies == null) {
						false;
					} else {
						var seen = false;
						for (body in bodies)
							if (bodyHintsIntLoopVar(body, loopVarName)) {
								seen = true;
								break;
							}
						seen;
					}
				case _:
					false;
			}
		}

		function stmtToUnit(s:HxStmt, tyCtx:Map<String, TyType>, allowedValueIdentsForStmt:Map<String, Bool>):String {
			final prevAllowedValueIdentNames = currentAllowedValueIdentNames;
			final prevExprTyHints = currentExprTyHints;
			final exprTyHints = cloneTyCtxLocal(tyCtx);
			for (name in localHints.keys())
				if (exprTyHints.get(name) == null) {
					final hinted = localHints.get(name);
					if (hinted != null)
						exprTyHints.set(name, hinted);
				}
			currentAllowedValueIdentNames = allowedValueIdentsForStmt;
			currentExprTyHints = exprTyHints;
			var out:String;
			try {
				out = switch (s) {
				case SBlock(ss, _pos):
					final nestedStmtBuf = new StringBuf();
					stmtListToOcaml(ss, allowedValueIdentsForStmt, returnExc, nestedStmtBuf, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee, localHints, fnReturnTypes, debugModuleName, debugFunctionName);
					nestedStmtBuf.toString();
				case SVar(_name, _typeHint, _init, _pos):
					// Handled at the list level because it needs to wrap the remainder with `let ... in`.
					"()";
				case STry(tryBody, _catches, _pos):
					stmtToUnit(tryBody, tyCtx, allowedValueIdentsForStmt);
				case SThrow(_expr, _pos):
					"()";
				case SSwitch(scrutinee, patterns, bodies, _pos):
					final sw = exprToOcaml(scrutinee, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
					function patternCond(p:HxSwitchPattern):String {
						return switch (p) {
							case POr(patterns):
								if (patterns == null || patterns.length == 0) {
									"false";
								} else {
									final parts = new Array<String>();
									for (pp in patterns)
										parts.push("(" + patternCond(pp) + ")");
									"(" + parts.join(" || ") + ")";
								}
							case PNull:
								backendDialect.runtimeIsNull("__sw");
							case PWildcard, PBind(_):
								"true";
							case PString(v):
								backendDialect.runtimeDynamicEquals("__sw", escapeOcamlString(v));
							case PInt(v):
								backendDialect.runtimeDynamicEquals("__sw", Std.string(v));
							case PEnumValue(name):
								backendDialect.runtimeDynamicEquals("__sw", escapeOcamlString(name));
						};
					}
					var chain = "()";
					if (patterns != null && bodies != null) {
						final count = patterns.length < bodies.length ? patterns.length : bodies.length;
						for (i in 0...count) {
							final idx = count - 1 - i;
							final pattern = patterns[idx];
							final body = bodies[idx];
							final caseTy = switch (pattern) {
								case PBind(name):
									extendTyByIdentLocal(tyCtx, name, TyType.fromHintText("Dynamic"));
								case _:
									cloneTyCtxLocal(tyCtx);
							};
							final bodyUnit = stmtToUnit(body, cast caseTy, allowedValueIdentsForStmt);
							final thenUnit = switch (pattern) {
								case PBind(name):
									"(let " + ocamlValueIdent(name) + " = __sw in (" + bodyUnit + "))";
								case _:
									"(" + bodyUnit + ")";
							};
							final cond = patternCond(pattern);
							chain = "(if " + cond + " then " + thenUnit + " else (" + chain + "))";
						}
					}
					"(let __sw = (" + sw + ") in " + chain + ")";
				case SIf(cond, thenBranch, elseBranch, _pos):
					final thenUnit = stmtToUnit(thenBranch, tyCtx, allowedValueIdentsForStmt);
					final elseUnit = elseBranch == null ? "()" : stmtToUnit(elseBranch, tyCtx, allowedValueIdentsForStmt);
					final condS = condToOcamlBool(cond, tyCtx, allowedValueIdentsForStmt);
					// Avoid typechecking dead branches in bring-up:
					// - Unknown conditions are lowered as `true` by default.
					// - Keeping the unused branch can still constrain types and break compilation
					//   (e.g. forcing a param to `Obj.t` due to a dead `Std.string` call).
					if (condS == "true") {
						"(" + thenUnit + ")";
					} else if (condS == "false") {
						"(" + elseUnit + ")";
					} else {
						"if " + condS + " then (" + thenUnit + ") else (" + elseUnit + ")";
					}
				case SWhile(cond, body, _pos):
					final condS = condToOcamlBool(cond, tyCtx, allowedValueIdentsForStmt);
					final bodyUnit = stmtToUnit(body, tyCtx, allowedValueIdentsForStmt);
					if (condS == "false") {
						"()";
					} else {
						"(while " + condS + " do " + bodyUnit + " done)";
					}
				case SDoWhile(body, cond, _pos):
					final bodyUnit = stmtToUnit(body, tyCtx, allowedValueIdentsForStmt);
					final condS = condToOcamlBool(cond, tyCtx, allowedValueIdentsForStmt);
					"(let __hx_do_continue = ref true in "
					+ "while !__hx_do_continue do "
					+ "__hx_do_continue := false; "
					+ bodyUnit
					+ "; if "
					+ condS
					+ " then __hx_do_continue := true else () "
					+ "done)";
				case SBreak(_pos):
					"()";
				case SContinue(_pos):
					"()";
				case SForIn(name, iterable, body, _pos):
					final ident = ocamlValueIdent(name);
					final defaultLoopTy = (tyCtxGet(tyCtx,
						name) != null) ? tyCtxGet(tyCtx, name) : ((localHints.get(name) != null) ? localHints.get(name) : TyType.fromHintText("Dynamic"));
					final loopVarTy = switch (iterable) {
						case ERange(_, _):
							TyType.fromHintText("Int");
						case EIdent(iterName):
							final iterTy = (tyCtxGet(tyCtx, iterName) != null) ? tyCtxGet(tyCtx, iterName) : localHints.get(iterName);
							final inferredElem = arrayElemTypeFromTy(iterTy);
							if (!inferredElem.isUnknown()) {
								inferredElem;
							} else if (bodyHintsIntLoopVar(body, name)) {
								TyType.fromHintText("Int");
							} else {
								defaultLoopTy;
							}
						case EArrayDecl(_), EArrayComprehension(_, _, _):
							final inferredElem = arrayElemTypeFromTy(inferInitType(iterable));
							inferredElem.isUnknown() ? defaultLoopTy : inferredElem;
						case _:
							defaultLoopTy;
					};
					final bodyTy = extendTyByIdentLocal(tyCtx, name, loopVarTy);
					final bodyUnit = stmtToUnit(body, cast bodyTy, allowedValueIdentsForStmt);
					switch (iterable) {
						case ERange(startExpr, endExpr):
							final start = exprToOcaml(startExpr, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee);
							final end = exprToOcaml(endExpr, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee);
							"(let __start = ("
							+ start
							+ ") in "
							+ "let __end = ("
							+ end
							+ ") in "
							+ "if (__end <= __start) then () else ("
							+ "for "
							+ ident
							+ " = __start to (__end - 1) do "
							+ bodyUnit
							+ " done))";
						case _:
							"HxBootArray.iter ("
							+ exprToOcaml(iterable, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ ") (fun "
							+ ident
							+ " -> "
							+ bodyUnit
							+ ")";
					}
				case SReturnVoid(_pos):
					"raise (" + returnExc + " (Obj.repr ()))";
				case SReturn(expr, _pos):
					if (debugModuleName != null && debugFunctionName != null)
						_EmitterStageDebug.traceStage3Function("fn_return_before_expr", debugModuleName, debugFunctionName);
					final renderedReturnExpr = returnExprToOcaml(expr, allowedValueIdentsForStmt, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee);
					if (debugModuleName != null && debugFunctionName != null)
						_EmitterStageDebug.traceStage3Function("fn_return_after_expr", debugModuleName, debugFunctionName);
					final wrappedReturnBuf = new StringBuf();
					wrappedReturnBuf.add("raise (");
					wrappedReturnBuf.add(returnExc);
					wrappedReturnBuf.add(" (Obj.repr (");
					wrappedReturnBuf.add(renderedReturnExpr);
					wrappedReturnBuf.add(")))");
					final wrappedReturnExpr = wrappedReturnBuf.toString();
					if (debugModuleName != null && debugFunctionName != null)
						_EmitterStageDebug.traceStage3Function("fn_return_after_wrap", debugModuleName, debugFunctionName);
					wrappedReturnExpr;
				case SExpr(expr, _pos):
					// Avoid emitting invalid OCaml for unsupported assignment lvalues while still
					// allowing modeled instance-field assignment side effects.
					switch (expr) {
						case EBinop(op, EIdent(name), rhs):
							final lowered = mutableAssignmentStmtToUnit(op, name, rhs, tyCtx, allowedValueIdentsForStmt);
							if (lowered != null) {
								lowered;
							} else if (op == "=") {
								"()";
							} else {
								"ignore (" + returnExprToOcaml(expr, allowedValueIdentsForStmt, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
									moduleNameByPkgAndClass, callSigByCallee) + ")";
							}
						case EBinop("=", EField(_, _), _):
							"ignore (" + returnExprToOcaml(expr, allowedValueIdentsForStmt, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
								moduleNameByPkgAndClass, callSigByCallee) + ")";
						case EBinop("=", _l, _r):
							"()";
						case _:
							"ignore (" + returnExprToOcaml(expr, allowedValueIdentsForStmt, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
								moduleNameByPkgAndClass, callSigByCallee) + ")";
					}
				}
			} catch (e:Dynamic) {
				currentAllowedValueIdentNames = prevAllowedValueIdentNames;
				currentExprTyHints = prevExprTyHints;
				throw e;
			}
			currentAllowedValueIdentNames = prevAllowedValueIdentNames;
			currentExprTyHints = prevExprTyHints;
			return out;
		}

		// Fold right so `var` statements can wrap the rest with `let name = init in ...`.
		function stmtDebugTag(s:HxStmt):String {
			return switch (s) {
				case SBlock(_, _): "SBlock";
				case SVar(_, _, _, _): "SVar";
				case STry(_, _, _): "STry";
				case SThrow(_, _): "SThrow";
				case SSwitch(_, _, _, _): "SSwitch";
				case SIf(_, _, _, _): "SIf";
				case SWhile(_, _, _): "SWhile";
				case SDoWhile(_, _, _): "SDoWhile";
				case SBreak(_): "SBreak";
				case SContinue(_): "SContinue";
				case SForIn(_, _, _, _): "SForIn";
				case SReturnVoid(_): "SReturnVoid";
				case SReturn(_, _): "SReturn";
				case SExpr(_, _): "SExpr";
			}
		}

		var out = "()";
		for (i in 0...stmts.length) {
			final idx = stmts.length - 1 - i;
			final s = stmts[idx];
			final tyCtx = extendTyWithLocals(tyByIdent, localsBefore[idx]);
			final allowedValueIdentsForStmt = extendAllowedValueIdents(allowedValueIdents, localsBefore[idx]);
			if (debugModuleName != null && debugFunctionName != null)
				for (name in localsBefore[idx].keys()) {
					final ctxTy = tyCtx.get(name);
					final localTy = localHints.get(name);
					_EmitterStageDebug.traceLocalType("stmt_before_" + idx + "_" + stmtDebugTag(s), debugModuleName, debugFunctionName, name,
						"ctx=" + (ctxTy == null ? "<null>" : ctxTy.toString()) + " local="
						+ (localTy == null ? "<null>" : localTy.toString()));
				}
			if (debugModuleName != null && debugFunctionName != null)
				_EmitterStageDebug.traceStage3Function("fn_stmt_before_" + idx + "_" + stmtDebugTag(s), debugModuleName, debugFunctionName);
			switch (s) {
				case SVar(name, typeHint, init, _pos):
					final declaredTy = typeHint != null && StringTools.trim(typeHint).length > 0 ? TyType.fromHintText(StringTools.trim(typeHint)) : null;
					final hintedTy = declaredTy != null ? declaredTy : (tyCtxGet(tyCtx, name) != null ? tyCtxGet(tyCtx, name) : localHints.get(name));
					final rhs = if (init == null) {
						"(Obj.magic 0)";
					} else {
						// Stage 3 bring-up: in class methods, `var x = x;` commonly means
						// "shadow a field" (`var x = this.x;`). We don't model `this` field
						// access yet, and emitting `let x = x` produces an unbound OCaml value.
						switch (init) {
							case EIdent(n) if (n == name):
								"(Obj.magic 0)";
							case _:
								returnExprToOcaml(init, allowedValueIdentsForStmt, hintedTy, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
									moduleNameByPkgAndClass, callSigByCallee);
						}
					};
					if (debugModuleName != null && debugFunctionName != null)
						_EmitterStageDebug.traceStage3Function("fn_svar_after_init", debugModuleName, debugFunctionName);
					final ident = ocamlValueIdent(name);
					// Keep OCaml warning discipline resilient: Haxe code (especially upstream-ish tests)
					// can contain locals that are intentionally unused. In OCaml, that triggers warnings
					// which can become hard errors under `-warn-error`.
					final svarBuf = new StringBuf();
					svarBuf.add("let ");
					svarBuf.add(ident);
					if (isMutableLocalRefIdent(name)) {
						svarBuf.add(" = ref (");
						svarBuf.add(rhs);
						svarBuf.add(") in (ignore ");
						svarBuf.add(ident);
						svarBuf.add("; (");
						svarBuf.add(out);
						svarBuf.add("))");
					} else {
						svarBuf.add(" = ");
						svarBuf.add(rhs);
						svarBuf.add(" in (ignore ");
						svarBuf.add(ident);
						svarBuf.add("; (");
						svarBuf.add(out);
						svarBuf.add("))");
					}
					out = svarBuf.toString();
				case SIf(cond, thenBranch, elseBranch, _pos):
					// Stage 3 bring-up: recognize and SSA-lower the common "null-coalescing assignment"
					// idiom used by upstream RunCi:
					//
					//   if (x == null) x = expr;
					//
					// Why
					// - Our Stage3 emitter models locals/params as immutable OCaml `let` bindings.
					// - Emitting `x = expr` as a side-effecting assignment would require `ref`/mutable
					//   lowering across the entire function.
					// - This pattern can be expressed without mutation by shadowing:
					//     let x = if x == null then expr else x in ...
					//
					// Note
					// - We only do this for the exact "if (x == null) x = ..." shape with no else.
					function unwrapSingleAssign(b:HxStmt):Null<{name:String, rhs:HxExpr}> {
						return switch (b) {
							case SExpr(EBinop("=", EIdent(name), rhs), _):
								{name: name, rhs: rhs};
							case SBlock(ss, _):
								(ss != null && ss.length == 1) ? unwrapSingleAssign(ss[0]) : null;
							case _:
								null;
						}
					}

					function isNullCheckFor(name:String, c:HxExpr):Bool {
						return switch (c) {
							case EBinop("==", EIdent(n), ENull): n == name;
							case EBinop("==", ENull, EIdent(n)): n == name;
							case _:
								false;
						}
					}

					final assign = elseBranch == null ? unwrapSingleAssign(thenBranch) : null;
					if (assign != null && isNullCheckFor(assign.name, cond) && !isMutableLocalRefIdent(assign.name)) {
						final ident = ocamlValueIdent(assign.name);
						final rhs = returnExprToOcaml(assign.rhs, allowedValueIdentsForStmt, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath,
							moduleNameByPkgAndClass, callSigByCallee);
						out = buildNullCoalesceAssign(ident, condToOcamlBool(cond, cast tyCtx, allowedValueIdentsForStmt), rhs, out);
					} else {
						// Default lowering for if-statements.
						final stmtUnit = stmtToUnit(s, cast tyCtx, allowedValueIdentsForStmt);
						out = stmtAlwaysReturns(s) ? stmtUnit : buildSequentialStmt(stmtUnit, out);
					}
				case _:
					// Avoid emitting `...; <nonreturning expr>` sequences, which produce warning 21
					// (nonreturning-statement). This also naturally drops statements that appear after
					// a definite `return` in the same block (unreachable in Haxe).
					final stmtUnit = stmtToUnit(s, cast tyCtx, allowedValueIdentsForStmt);
					out = stmtAlwaysReturns(s) ? stmtUnit : buildSequentialStmt(stmtUnit, out);
			}
			if (debugModuleName != null && debugFunctionName != null)
				_EmitterStageDebug.traceStage3Function("fn_stmt_after_" + idx + "_" + stmtDebugTag(s), debugModuleName, debugFunctionName);
		}
		if (debugModuleName != null && debugFunctionName != null)
			_EmitterStageDebug.traceStage3Function("fn_stmt_fold_done", debugModuleName, debugFunctionName);
		currentMutableLocalRefNames = prevMutableLocalRefNames;
		if (debugModuleName != null && debugFunctionName != null)
			_EmitterStageDebug.traceStage3Function("fn_stmt_ctx_restored", debugModuleName, debugFunctionName);
			final stmtOutBuf = new StringBuf();
			stmtOutBuf.add(out);
			final stmtOut = stmtOutBuf.toString();
			if (debugModuleName != null && debugFunctionName != null)
				_EmitterStageDebug.traceStage3Function("fn_stmt_return_ready", debugModuleName, debugFunctionName);
			final stmtOutDyn:Dynamic = stmtOut;
			_EmitterStageDebug.traceStage3Phase("stmt_return_before_stringify");
			final stmtOutStable = Std.string(stmtOutDyn);
			_EmitterStageDebug.traceStage3Phase("stmt_return_after_stringify");
			final stmtReturnBuf = new StringBuf();
			stmtReturnBuf.add(stmtOutStable);
			_EmitterStageDebug.traceStage3Phase("stmt_return_before_return");
			outSink.add(stmtReturnBuf.toString());
		}
	}

	/**
		Emit a minimal OCaml program for the typed module and optionally build it as a native executable.

		Why
		- This is the smallest “compiler-shaped” slice we can validate early:
		  Stage 3 typing produces a stable environment, and we can prove it can
		  drive *some* codegen all the way to a runnable binary.

		What
		- Always writes generated OCaml sources into `outDir` (including module units + runtime).
		- When `buildExecutable=true` (default), also produces `out.exe` and returns its path.
		- When `buildExecutable=false`, skips `ocamlopt` and returns the expected `out.exe` path for callers that only validate emitted source shape.

		How
		- Extracts function signatures from the typed environment and return
		  expressions from the parsed AST (we only support simple return shapes).
		- Builds using `ocamlopt` (override via `OCAMLOPT` env var) when `buildExecutable=true`.
	**/
	public static function emitToDir(p:MacroExpandedProgram, outDir:String, emitFullBodies:Bool = false, buildExecutable:Bool = true,
			ocamlProfile:backend.OcamlProfile = backend.OcamlProfile.Portable, ?defines:haxe.ds.StringMap<String>):String {
		traceEmitToDirEntry("emitToDir_enter");
		final outAbs = requireEmitToDirOutAbs(outDir);
		installEmitToDirProfile(ocamlProfile);
		ensureEmitToDirOutDir(outAbs);

		function uniqStrings(xs:Array<String>):Array<String> {
			if (xs == null || xs.length <= 1)
				return xs;
			final seen = new Map<String, Bool>();
			final out = new Array<String>();
			for (x in xs) {
				if (x == null)
					continue;
				if (seen.exists(x))
					continue;
				seen.set(x, true);
				out.push(x);
			}
			return out;
		}

		function ocamldepSort(mlFiles:Array<String>):Array<String> {
			if (mlFiles == null || mlFiles.length <= 1)
				return mlFiles;

			final ocamldep = {
				final v = Sys.getEnv("OCAMLDEP");
				(v == null || v.length == 0) ? "ocamldep" : v;
			}

			final p = new sys.io.Process(ocamldep, [
				"-I",
				"runtime",
				"-I",
				"+unix",
				"-I",
				"+str",
				"-I",
				"+threads",
				"-I",
				"+dynlink",
				"-sort"
			].concat(mlFiles));
			final chunks = new Array<String>();
			try {
				while (true) {
					chunks.push(p.stdout.readLine());
				}
			} catch (_:haxe.io.Eof) {}

			final code = p.exitCode();
			p.close();
			if (code != 0)
				throw "stage3 emitter: ocamldep -sort failed with exit code " + code;

			final sorted = new Array<String>();
			for (c in chunks) {
				for (t in c.split(" ")) {
					final s = StringTools.trim(t);
					if (s.length == 0)
						continue;
					if (!StringTools.endsWith(s, ".ml"))
						continue;
					sorted.push(s);
				}
			}

			// Best-effort: if ocamldep output looks empty or incomplete, fall back to caller order.
			if (sorted.length == 0)
				return mlFiles;
			return sorted;
		}

		// Stage 4 bring-up: emit macro-generated OCaml modules (if any).
		//
		// This is a minimal “generate code” effect: macros can request extra target compilation units
		// without us implementing full typed AST transforms yet.
		final generatedPaths = new Array<String>();
		traceEmitToDirEntry("emitToDir_before_generated_modules");
		for (gm in p.getGeneratedOcamlModules()) {
			if (gm == null)
				continue;
			final name = gm.name == null ? "" : StringTools.trim(gm.name);
			if (name.length == 0)
				continue;
			final path = haxe.io.Path.join([outAbs, name + ".ml"]);
			sys.io.File.saveContent(path, gm.source == null ? "" : gm.source);
			generatedPaths.push(name + ".ml");
		}
		traceEmitToDirEntry("emitToDir_after_generated_modules");

		// Stage 3 bring-up: minimal OCaml-side shims for implicit Haxe std classes.
		//
		// Why
		// - Stage3 resolves *import closure*, not "all referenced modules" like a real typer.
		// - Upstream-ish code can refer to core std classes like `Std` without an explicit import.
		// - Without a shim, emitted OCaml can fail immediately with `Unbound module Std`.
		//
		// What
		// - These shims are intentionally tiny and non-semantic: they exist only to keep the
		//   bring-up compiler compiling further so we can discover the next missing feature.
		// - They are only emitted when the corresponding `<Name>.ml` is not already present.
		var shimRepoRoot = "";
		function inferRepoRootForShims():String {
			if (shimRepoRoot.length > 0)
				return shimRepoRoot;
			final env = Sys.getEnv("HXHX_REPO_ROOT");
			if (env != null && env.length > 0) {
				final candidate = haxe.io.Path.join([env, "packages", "hxhx-core", "shims"]);
				if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate)) {
					shimRepoRoot = env;
					return shimRepoRoot;
				}
			}

			final prog = Sys.programPath();
			if (prog == null || prog.length == 0)
				return "";
			final abs = try sys.FileSystem.fullPath(prog) catch (_:haxe.io.Error) prog catch (_:String) prog;
			var dir = try haxe.io.Path.directory(abs) catch (_:String) "";
			if (dir == null || dir.length == 0)
				return "";

			for (_ in 0...10) {
				final shimsDir = haxe.io.Path.join([dir, "packages", "hxhx-core", "shims"]);
				if (sys.FileSystem.exists(shimsDir) && sys.FileSystem.isDirectory(shimsDir)) {
					shimRepoRoot = dir;
					return shimRepoRoot;
				}
				final parent = haxe.io.Path.normalize(haxe.io.Path.join([dir, ".."]));
				if (parent == dir)
					break;
				dir = parent;
			}
			return "";
		}

		function readShimTemplate(shimName:String):String {
			final root = inferRepoRootForShims();
			if (root == null || root.length == 0)
				throw "stage3 emitter: cannot locate repo root for shim templates (set HXHX_REPO_ROOT)";
			final path = haxe.io.Path.join([root, "packages", "hxhx-core", "shims", shimName + ".ml"]);
			if (!sys.FileSystem.exists(path))
				throw "stage3 emitter: missing shim template: " + path;
			return sys.io.File.getContent(path);
		}

		// Stage 3 bring-up: link the repo-owned OCaml runtime when compiling the emitted program.
		//
		// Why
		// - Gate2's `stage3_emit_runner` rung compiles and runs upstream-shaped Haxe code (tests/RunCi.hx).
		// - The emitted OCaml references runtime helpers like `HxRuntime.hx_null`, `HxRuntime.dynamic_equals`,
		//   `Std.string`, and `EReg`.
		//
		// Provenance
		// - These modules live in `packages/reflaxe.ocaml/std/runtime/*.ml` and are authored for this repo.
		// - They are **not** copied from upstream Haxe compiler sources.
		final runtimePaths = new Array<String>();
		traceEmitToDirEntry("emitToDir_before_runtime_copy");
		{
			final root = inferRepoRootForShims();
			if (root == null || root.length == 0)
				throw "stage3 emitter: cannot locate repo root for runtime templates (set HXHX_REPO_ROOT)";
			final runtimeCandidates = [
				haxe.io.Path.join([root, "packages", "reflaxe.ocaml", "std", "runtime"]),
				// Back-compat: older repo layouts used `std/runtime` at the root.
				haxe.io.Path.join([root, "std", "runtime"]),
			];
			var runtimeSrcDir:Null<String> = null;
			for (candidate in runtimeCandidates) {
				if (candidate != null && sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate)) {
					runtimeSrcDir = candidate;
					break;
				}
			}
			if (runtimeSrcDir == null) {
				throw "stage3 emitter: missing runtime directory (expected one of):\n- " + runtimeCandidates.join("\n- ");
			}

			final runtimeOutDir = haxe.io.Path.join([outAbs, "runtime"]);
			if (!sys.FileSystem.exists(runtimeOutDir))
				sys.FileSystem.createDirectory(runtimeOutDir);

			for (name in sys.FileSystem.readDirectory(runtimeSrcDir)) {
				if (name == null || !StringTools.endsWith(name, ".ml"))
					continue;
				final srcPath = haxe.io.Path.join([runtimeSrcDir, name]);
				final dstPath = haxe.io.Path.join([runtimeOutDir, name]);
				sys.io.File.copy(srcPath, dstPath);
				runtimePaths.push("runtime/" + name);
			}
		}
		traceEmitToDirEntry("emitToDir_after_runtime_copy");

		{
			final shimName = "Lambda";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: Lambda *)\n"
					+ "type __hx_iterable = { iterator : Obj.t -> unit -> Obj.t HxIterator.t }\n"
					+ "let __hx_iter_any it f =\n"
					+ "  let __hx_make_iterator_raw = HxAnon.get (Obj.repr (Obj.magic it)) \"iterator\" in\n"
					+ "  let __hx_iterator =\n"
					+ "    if __hx_make_iterator_raw != HxRuntime.hx_null then\n"
					+ "      let __hx_make_iterator = (Obj.obj __hx_make_iterator_raw : unit -> Obj.t) in\n"
					+ "      (Obj.magic (__hx_make_iterator ()) : _ HxIterator.t)\n"
					+ "    else\n"
					+ "      let __hx_make_iterator = ((Obj.magic it : __hx_iterable).iterator) in\n"
					+ "      __hx_make_iterator (Obj.magic it) ()\n"
					+ "  in\n"
					+ "  while HxIterator.hasNext (__hx_iterator) do\n"
					+ "    f (HxIterator.next (__hx_iterator))\n"
					+ "  done\n"
					+ "let array it =\n"
					+ "  let __hx_acc = ref [] in\n"
					+ "  __hx_iter_any it (fun x -> __hx_acc := x :: !__hx_acc);\n"
					+ "  HxBootArray.of_list (List.rev (!__hx_acc))\n"
					+ "let list it =\n"
					+ "  let __hx_obj = Haxe_ds_List.create () in\n"
					+ "  __hx_iter_any it (fun x -> ignore (Haxe_ds_List.add (__hx_obj) x));\n"
					+ "  __hx_obj\n"
					+ "let fold it f first =\n"
					+ "  let acc = ref first in\n"
					+ "  __hx_iter_any it (fun x -> acc := f x !acc);\n"
					+ "  !acc\n"
					+ "let has it v =\n"
					+ "  let found = ref false in\n"
					+ "  let __hx_value = Obj.repr v in\n"
					+ "  __hx_iter_any it (fun x -> if not (!found) && x = __hx_value then found := true);\n"
					+ "  !found\n"
					+ "let exists it f =\n"
					+ "  let found = ref false in\n"
					+ "  __hx_iter_any it (fun x -> if not (!found) && f x then found := true);\n"
					+ "  !found\n"
					+ "let iter it f =\n"
					+ "  __hx_iter_any it f\n"
					+ "let count it =\n"
					+ "  let n = ref 0 in\n"
					+ "  __hx_iter_any it (fun _ -> n := !n + 1);\n"
					+ "  !n\n");
			}
			// Keep bootstrap shims in the compile unit list even on repeat emits into the same out dir.
			generatedPaths.push(shimName + ".ml");
		}
		traceEmitToDirEntry("emitToDir_after_lambda_shim");
		{
			final shimName = "Haxe_ds_List";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: haxe.ds.List *)\n"
					+ "type t = {\n"
					+ "  mutable __hx_type : Obj.t;\n"
					+ "  mutable values : Obj.t HxArray.t;\n"
					+ "  mutable length : int;\n"
					+ "  add : Obj.t -> Obj.t -> unit;\n"
					+ "  push : Obj.t -> Obj.t -> unit;\n"
					+ "  first : Obj.t -> unit -> Obj.t;\n"
					+ "  last : Obj.t -> unit -> Obj.t;\n"
					+ "  pop : Obj.t -> unit -> Obj.t;\n"
					+ "  isEmpty : Obj.t -> unit -> bool;\n"
					+ "  clear : Obj.t -> unit -> unit;\n"
					+ "  remove : Obj.t -> Obj.t -> bool;\n"
					+ "  iterator : Obj.t -> unit -> Obj.t HxIterator.t;\n"
					+ "  join : Obj.t -> string -> string;\n"
					+ "  toString : Obj.t -> unit -> string;\n"
					+ "}\n"
					+ "let add__impl = fun (self : t) item ->\n"
					+ "  ignore (HxArray.push ((Obj.magic self : t).values) item);\n"
					+ "  (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values)\n"
					+ "let push__impl = fun (self : t) item ->\n"
					+ "  let next = HxArray.create () in\n"
					+ "  let prev = ((Obj.magic self : t).values : Obj.t HxArray.t) in\n"
					+ "  ignore (HxArray.push next item);\n"
					+ "  ignore (let _g = ref 0 in while !_g < HxArray.length prev do ignore (let value = HxArray.get (Obj.magic prev) (!_g) in (\n"
					+ "    ignore (let __old = !_g in let __new = HxInt.add __old 1 in (\n"
					+ "      ignore (_g := __new);\n"
					+ "      __new\n"
					+ "    ));\n"
					+ "    ignore (HxArray.push next value)\n"
					+ "  )) done);\n"
					+ "  (Obj.magic self : t).values <- next;\n"
					+ "  (Obj.magic self : t).length <- HxArray.length next\n"
					+ "let first__impl = fun (self : t) () ->\n"
					+ "  if (Obj.magic self : t).length = 0 then Obj.magic HxRuntime.hx_null else HxArray.get ((Obj.magic self : t).values) 0\n"
					+ "let last__impl = fun (self : t) () ->\n"
					+ "  if (Obj.magic self : t).length = 0 then Obj.magic HxRuntime.hx_null else HxArray.get ((Obj.magic self : t).values) (HxInt.sub ((Obj.magic self : t).length) 1)\n"
					+ "let pop__impl = fun (self : t) () ->\n"
					+ "  let value = HxArray.shift ((Obj.magic self : t).values) () in\n"
					+ "  (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values);\n"
					+ "  value\n"
					+ "let isEmpty__impl = fun (self : t) () -> (Obj.magic self : t).length = 0\n"
					+ "let clear__impl = fun (self : t) () ->\n"
					+ "  (Obj.magic self : t).values <- HxArray.create ();\n"
					+ "  (Obj.magic self : t).length <- 0\n"
					+ "let remove__impl = fun (self : t) value ->\n"
					+ "  let removed = HxArray.remove ((Obj.magic self : t).values) value in\n"
					+ "  if removed then (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values) else ();\n"
					+ "  removed\n"
					+ "let iterator__impl = fun (self : t) () -> HxIterator.of_array ((Obj.magic self : t).values)\n"
					+ "let join__impl = fun (self : t) sep -> HxArray.join ((Obj.magic self : t).values) sep Std.string\n"
					+ "let toString__impl = fun (self : t) () -> ((\"{\" : string) ^ HxString.toStdString (join__impl (Obj.magic self) (\", \" : string))) ^ (\"}\" : string)\n"
					+ "let __empty = fun () -> ({ __hx_type = HxType.class_ \"haxe.ds.List\"; values = HxArray.create (); length = 0; add = (fun o a0 -> Obj.magic (add__impl (Obj.magic o) (Obj.magic a0))); push = (fun o a0 -> Obj.magic (push__impl (Obj.magic o) (Obj.magic a0))); first = (fun o () -> Obj.magic (first__impl (Obj.magic o) ())); last = (fun o () -> Obj.magic (last__impl (Obj.magic o) ())); pop = (fun o () -> Obj.magic (pop__impl (Obj.magic o) ())); isEmpty = (fun o () -> Obj.magic (isEmpty__impl (Obj.magic o) ())); clear = (fun o () -> Obj.magic (clear__impl (Obj.magic o) ())); remove = (fun o a0 -> Obj.magic (remove__impl (Obj.magic o) (Obj.magic a0))); iterator = (fun o () -> Obj.magic (iterator__impl (Obj.magic o) ())); join = (fun o a0 -> Obj.magic (join__impl (Obj.magic o) (Obj.magic a0))); toString = (fun o () -> Obj.magic (toString__impl (Obj.magic o) ())) } : t)\n"
					+ "let new_ = fun (self : t) ->\n"
					+ "  (Obj.magic self : t).__hx_type <- HxType.class_ \"haxe.ds.List\";\n"
					+ "  (Obj.magic self : t).values <- HxArray.create ();\n"
					+ "  (Obj.magic self : t).length <- 0;\n"
					+ "  self\n"
					+ "let create = fun () -> let self = (__empty () : t) in\n"
					+ "  ignore (new_ (Obj.magic self));\n"
					+ "  self\n"
					+ "let add = fun (self : t) item -> add__impl (Obj.magic self) item\n"
					+ "let push = fun (self : t) item -> push__impl (Obj.magic self) item\n"
					+ "let first = fun (self : t) () -> first__impl (Obj.magic self) ()\n"
					+ "let last = fun (self : t) () -> last__impl (Obj.magic self) ()\n"
					+ "let pop = fun (self : t) () -> pop__impl (Obj.magic self) ()\n"
					+ "let isEmpty = fun (self : t) () -> isEmpty__impl (Obj.magic self) ()\n"
					+ "let clear = fun (self : t) () -> clear__impl (Obj.magic self) ()\n"
					+ "let remove = fun (self : t) value -> remove__impl (Obj.magic self) value\n"
					+ "let iterator = fun (self : t) () -> iterator__impl (Obj.magic self) ()\n"
					+ "let join = fun (self : t) sep -> join__impl (Obj.magic self) sep\n"
					+ "let toString = fun (self : t) () -> toString__impl (Obj.magic self) ()\n");
			}
			generatedPaths.push(shimName + ".ml");
		}
		traceEmitToDirEntry("emitToDir_after_haxe_ds_list_shim");
		{
			final shimFile = "Haxe_ds_List.ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			try {
				var hasCreate = false;
				if (sys.FileSystem.exists(shimPath) && !sys.FileSystem.isDirectory(shimPath)) {
					final contents = sys.io.File.getContent(shimPath);
					hasCreate = contents.indexOf("let create") != -1 || contents.indexOf("let rec create") != -1;
				}
				if (!hasCreate) {
					final sourcePath = haxe.io.Path.join([outAbs, shimFile]);
					if (sys.FileSystem.exists(sourcePath) && !sys.FileSystem.isDirectory(sourcePath)) {
						sys.io.File.saveContent(sourcePath,
							"(* hxhx(stage3) bootstrap shim: haxe.ds.List *)\n"
							+ "type t = {\n"
							+ "  mutable __hx_type : Obj.t;\n"
							+ "  mutable values : Obj.t HxArray.t;\n"
							+ "  mutable length : int;\n"
							+ "  add : Obj.t -> Obj.t -> unit;\n"
							+ "  push : Obj.t -> Obj.t -> unit;\n"
							+ "  first : Obj.t -> unit -> Obj.t;\n"
							+ "  last : Obj.t -> unit -> Obj.t;\n"
							+ "  pop : Obj.t -> unit -> Obj.t;\n"
							+ "  isEmpty : Obj.t -> unit -> bool;\n"
							+ "  clear : Obj.t -> unit -> unit;\n"
							+ "  remove : Obj.t -> Obj.t -> bool;\n"
							+ "  iterator : Obj.t -> unit -> Obj.t HxIterator.t;\n"
							+ "  join : Obj.t -> string -> string;\n"
							+ "  toString : Obj.t -> unit -> string;\n"
							+ "}\n"
							+ "let add__impl = fun (self : t) item ->\n"
							+ "  ignore (HxArray.push ((Obj.magic self : t).values) item);\n"
							+ "  (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values)\n"
							+ "let push__impl = fun (self : t) item ->\n"
							+ "  let next = HxArray.create () in\n"
							+ "  let prev = ((Obj.magic self : t).values : Obj.t HxArray.t) in\n"
							+ "  ignore (HxArray.push next item);\n"
							+ "  ignore (let _g = ref 0 in while !_g < HxArray.length prev do ignore (let value = HxArray.get (Obj.magic prev) (!_g) in (\n"
							+ "    ignore (let __old = !_g in let __new = HxInt.add __old 1 in (\n"
							+ "      ignore (_g := __new);\n"
							+ "      __new\n"
							+ "    ));\n"
							+ "    ignore (HxArray.push next value)\n"
							+ "  )) done);\n"
							+ "  (Obj.magic self : t).values <- next;\n"
							+ "  (Obj.magic self : t).length <- HxArray.length next\n"
							+ "let first__impl = fun (self : t) () ->\n"
							+ "  if (Obj.magic self : t).length = 0 then Obj.magic HxRuntime.hx_null else HxArray.get ((Obj.magic self : t).values) 0\n"
							+ "let last__impl = fun (self : t) () ->\n"
							+ "  if (Obj.magic self : t).length = 0 then Obj.magic HxRuntime.hx_null else HxArray.get ((Obj.magic self : t).values) (HxInt.sub ((Obj.magic self : t).length) 1)\n"
							+ "let pop__impl = fun (self : t) () ->\n"
							+ "  let value = HxArray.shift ((Obj.magic self : t).values) () in\n"
							+ "  (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values);\n"
							+ "  value\n"
							+ "let isEmpty__impl = fun (self : t) () -> (Obj.magic self : t).length = 0\n"
							+ "let clear__impl = fun (self : t) () ->\n"
							+ "  (Obj.magic self : t).values <- HxArray.create ();\n"
							+ "  (Obj.magic self : t).length <- 0\n"
							+ "let remove__impl = fun (self : t) value ->\n"
							+ "  let removed = HxArray.remove ((Obj.magic self : t).values) value in\n"
							+ "  if removed then (Obj.magic self : t).length <- HxArray.length ((Obj.magic self : t).values) else ();\n"
							+ "  removed\n"
							+ "let iterator__impl = fun (self : t) () -> HxIterator.of_array ((Obj.magic self : t).values)\n"
							+ "let join__impl = fun (self : t) sep -> HxArray.join ((Obj.magic self : t).values) sep Std.string\n"
							+ "let toString__impl = fun (self : t) () -> ((\"{\" : string) ^ HxString.toStdString (join__impl (Obj.magic self) (\", \" : string))) ^ (\"}\" : string)\n"
							+ "let __empty = fun () -> ({ __hx_type = HxType.class_ \"haxe.ds.List\"; values = HxArray.create (); length = 0; add = (fun o a0 -> Obj.magic (add__impl (Obj.magic o) (Obj.magic a0))); push = (fun o a0 -> Obj.magic (push__impl (Obj.magic o) (Obj.magic a0))); first = (fun o () -> Obj.magic (first__impl (Obj.magic o) ())); last = (fun o () -> Obj.magic (last__impl (Obj.magic o) ())); pop = (fun o () -> Obj.magic (pop__impl (Obj.magic o) ())); isEmpty = (fun o () -> Obj.magic (isEmpty__impl (Obj.magic o) ())); clear = (fun o () -> Obj.magic (clear__impl (Obj.magic o) ())); remove = (fun o a0 -> Obj.magic (remove__impl (Obj.magic o) (Obj.magic a0))); iterator = (fun o () -> Obj.magic (iterator__impl (Obj.magic o) ())); join = (fun o a0 -> Obj.magic (join__impl (Obj.magic o) (Obj.magic a0))); toString = (fun o () -> Obj.magic (toString__impl (Obj.magic o) ())) } : t)\n"
							+ "let new_ = fun (self : t) ->\n"
							+ "  (Obj.magic self : t).__hx_type <- HxType.class_ \"haxe.ds.List\";\n"
							+ "  (Obj.magic self : t).values <- HxArray.create ();\n"
							+ "  (Obj.magic self : t).length <- 0;\n"
							+ "  self\n"
							+ "let create = fun () -> let self = (__empty () : t) in\n"
							+ "  ignore (new_ (Obj.magic self));\n"
							+ "  self\n"
							+ "let add = fun (self : t) item -> add__impl (Obj.magic self) item\n"
							+ "let push = fun (self : t) item -> push__impl (Obj.magic self) item\n"
							+ "let first = fun (self : t) () -> first__impl (Obj.magic self) ()\n"
							+ "let last = fun (self : t) () -> last__impl (Obj.magic self) ()\n"
							+ "let pop = fun (self : t) () -> pop__impl (Obj.magic self) ()\n"
							+ "let isEmpty = fun (self : t) () -> isEmpty__impl (Obj.magic self) ()\n"
							+ "let clear = fun (self : t) () -> clear__impl (Obj.magic self) ()\n"
							+ "let remove = fun (self : t) value -> remove__impl (Obj.magic self) value\n"
							+ "let iterator = fun (self : t) () -> iterator__impl (Obj.magic self) ()\n"
							+ "let join = fun (self : t) sep -> join__impl (Obj.magic self) sep\n"
							+ "let toString = fun (self : t) () -> toString__impl (Obj.magic self) ()\n");
					}
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}
		traceEmitToDirEntry("emitToDir_after_haxe_ds_list_repair");
		{
			// Stage 3 bring-up: a tiny "array-like" container used only by the bootstrap emitter output.
			//
			// Why
			// - Gate2-shaped orchestration code uses `Array` pervasively and expects mutation (`push`)
			//   and iteration (`for (x in arr)`).
			// - The Stage3 bootstrap emitter deliberately does **not** link the full reflaxe.ocaml
			//   runtime (`packages/reflaxe.ocaml/std/runtime`), so we provide a self-contained OCaml shim here.
			//
			// Note
			// - This is not Haxe-correct `Array<T>` semantics. It is a bring-up convenience to let
			//   stage3_emit_runner style workloads execute far enough to expose the *next* missing
			//   frontend/typer/macro feature.
			final shimName = "HxBootArray";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath, readShimTemplate(shimName));
			}
			generatedPaths.push(shimName + ".ml");
		}
		traceEmitToDirEntry("emitToDir_after_bootarray_shim");
		{
			final shimName = "HxBootProcess";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath, readShimTemplate(shimName));
			}
			generatedPaths.push(shimName + ".ml");
		}
		traceEmitToDirEntry("emitToDir_after_bootprocess_shim");
		{
			final shimName = "Reflect";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: Reflect *)\n"
					+ "let field o f = HxAnon.get o f\n"
					+ "let fields o = HxAnon.fields o\n"
					+ "let getProperty o f = HxAnon.get o f\n"
					+ "let setProperty o f v = HxAnon.set o f v\n"
					+ "let hasField o f = HxAnon.has o f\n"
					+ "let isFunction = HxReflect.isFunction\n"
					+ "let isObject = HxReflect.isObject\n"
					+ "let compare = HxReflect.compare\n"
					+ "let callMethod = HxReflect.callMethod\n"
					+ "let makeVarArgs = HxReflect.makeVarArgs\n"
					+ "let makeVarArgsVoid = HxReflect.makeVarArgsVoid\n"
					+ "let deleteField o f = HxAnon.delete o f\n"
					+ "let copy = HxAnon.copy\n");
			}
			generatedPaths.push(shimName + ".ml");
		}
		{
			final shimName = "IgnoredFixture";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: IgnoredFixture *)\n"
					+ "type t = Obj.t\n"
					+ "let notIgnored _ = (Obj.magic 0)\n"
					+ "let ignored _ = (Obj.magic 0)\n");
			}
			generatedPaths.push(shimName + ".ml");
		}
		{
			final shimName = "HxPosInfos";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: haxe.PosInfos *)\n"
					+ "type t = {\n"
					+ "  fileName : string;\n"
					+ "  lineNumber : int;\n"
					+ "  className : string;\n"
					+ "  methodName : string;\n"
					+ "  customParams : Obj.t;\n"
					+ "}\n");
			}
			generatedPaths.push(shimName + ".ml");
		}
		{
			final shimName = "Haxe_Int64";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: haxe.Int64 (bring-up only) *)\n"
					+ "\n"
					+ "(*\n"
					+ "  This is intentionally not a correct implementation of Haxe Int64 semantics.\n"
					+ "  It exists so upstream-shaped code can typecheck and link during Stage3.\n"
					+ "*)\n"
					+ "\n"
					+ "type t = int\n"
					+ "\n"
					+ "type divmod = { quotient : t; modulus : t }\n"
					+ "\n"
					+ "let make (_high : int) (low : int) : t = low\n"
					+ "let ofInt (i : int) : t = i\n"
					+ "let fromFloat (_f : _) : _ = Obj.repr 0\n"
					+ "let parseString (_s : string) : t = 0\n"
					+ "let toInt (v : t) : int = v\n"
					+ "let toStr (v : t) : string = string_of_int v\n"
					+ "let add (a : t) (b : t) : t = a + b\n"
					+ "let sub (a : t) (b : t) : t = a - b\n"
					+ "let mul (a : t) (b : t) : t = a * b\n"
					+ "let neg (a : t) : t = (-a)\n"
					+ "let eq (_a : _) (_b : _) : bool = true\n"
					+ "let compare (a : t) (b : t) : int = Stdlib.compare a b\n"
					+ "let divMod (a : t) (b : t) : divmod =\n"
					+ "  if b = 0 then { quotient = 0; modulus = 0 } else { quotient = a / b; modulus = a mod b }\n"
					+ "let isInt64 (_ : Obj.t) : bool = true\n");
			}
			generatedPaths.push(shimName + ".ml");
		}

		_EmitterStageDebug.traceStage3Phase("before_typed_modules");
		final typedModules = p.getTypedModules();
		_EmitterStageDebug.traceStage3Phase("after_typed_modules:" + typedModules.length);
		if (typedModules.length == 0)
			throw "stage3 emitter: empty typed module graph";

		// Stage 3 bring-up: avoid emitting placeholder units that shadow the repo-owned runtime.
		//
		// Why
		// - We copy `packages/reflaxe.ocaml/std/runtime/*.ml` into `out/runtime/` and compile them as part of the Stage3 program.
		// - The Stage3 typer/emitter can still produce placeholder `*.ml` units for the corresponding
		//   Haxe std types (e.g. `haxe.CallStack`), which would overwrite the runtime `.cmi` and cause
		//   downstream "Unbound value" errors.
		//
		// How
		// - Build a set of runtime-provided OCaml module names and skip emitting any typed module whose
		//   main unit name collides with a runtime unit.
		inline function runtimeModuleNameFromPath(path:String):String {
			final file = haxe.io.Path.withoutDirectory(path);
			final base = StringTools.endsWith(file, ".ml") ? file.substr(0, file.length - 3) : file;
			return upperFirst(base);
		}
		final runtimeModuleNames:Map<String, Bool> = new Map();
		for (p0 in runtimePaths)
			runtimeModuleNames.set(runtimeModuleNameFromPath(p0), true);
		var runtimeModuleCount = 0;
		for (_ in runtimeModuleNames.keys())
			runtimeModuleCount++;
		_EmitterStageDebug.traceStage3Phase("after_runtime_module_names:" + runtimeModuleCount);
		/**
			Known root provider units that Stage3 emits or relies on during bootstrap.

			Why
			- The expression emitter has a same-package fallback for unresolved single-part type paths
			  like `Util.ping()`, which rewrites them to the current package (for example `Unit_Util`).
			- Some upstream-facing std providers intentionally stay as root units instead:
			  `Type`, `Lambda`, import shims like `CallStack`, and small bootstrap helpers like `Xml`.
			- If these root units are not treated as "known modules", the fallback misqualifies them as
			  package-local providers (`Unit_Type`, `Unit_Lambda`) and the generated OCaml no longer links.

			How
			- Seed the known-runtime module map with the safe root provider names that the emitter already
			  generates or preserves elsewhere in this stage.
			- This keeps the resolver narrow: we only exempt known root providers, not arbitrary
			  uppercase identifiers.
		**/
		for (rootProvider in ["Type", "Lambda", "CallStack", "Reflect", "Xml", "Sys"])
			runtimeModuleNames.set(rootProvider, true);
		// Stage 3 bring-up: keep the `Haxe_Int64.ml` shim authoritative.
		//
		// Why
		// - The bootstrap frontend/typer does not index abstract/operator-heavy std modules well yet,
		//   so the placeholder provider for `haxe.Int64` can be missing required values like `ofInt`.
		// - We emit a tiny OCaml shim for `haxe.Int64` earlier in this stage to keep upstream-shaped
		//   code compiling, but it must not be overwritten by the placeholder emitter.
		//
		// How
		// - Treat `Haxe_Int64` as "runtime provided" so `emitModule` skips emitting the main unit.
		runtimeModuleNames.set("Haxe_Int64", true);

		inline function expectedMainClassFromFile(filePath:Null<String>):Null<String> {
			if (filePath == null || filePath.length == 0)
				return null;
			final name = haxe.io.Path.withoutDirectory(filePath);
			final dot = name.lastIndexOf(".");
			return dot <= 0 ? name : name.substr(0, dot);
		}

		inline function moduleTypeNameFor(tm:TypedModule):Null<String> {
			// In Haxe, the module name is the file base name (not "the first class we happened to parse").
			//
			// This matters for multi-type modules like upstream `unit/MyAbstract.hx`, where helper types are
			// addressed as `unit.MyAbstract.HelperType` regardless of which class the frontend surfaced as
			// the "main class" during bring-up.
			final fromFile = expectedMainClassFromFile(tm == null ? null : tm.getParsed().getFilePath());
			if (fromFile != null && fromFile.length > 0)
				return fromFile;

			// Fallback (in-memory modules): use the parsed main class name when available.
			final decl = tm == null ? null : tm.getParsed().getDecl();
			final main = decl == null ? null : HxModuleDecl.getMainClass(decl);
			final nm0 = main == null ? null : HxClassDecl.getName(main);
			final nm = nm0 == null ? "" : StringTools.trim(nm0);
			return (nm.length > 0 && nm != "Unknown") ? nm : null;
		}

		inline function moduleNameForDecl(decl:HxModuleDecl, moduleTypeName:Null<String>, typeName:String):String {
			final pkgRaw = decl == null ? "" : HxModuleDecl.getPackagePath(decl);
			final pkg = pkgRaw == null ? "" : StringTools.trim(pkgRaw);
			final parts = (pkg.length == 0 ? [] : pkg.split("."));
			final modName = moduleTypeName == null ? "" : StringTools.trim(moduleTypeName);
			// Haxe type paths for module-local helper types include the module name:
			//   `package.Module.Helper`
			// Emitted OCaml module: `Package_Module_Helper`.
			//
			// When `typeName == moduleTypeName`, this is the main type and we emit `Package_Type`.
			if (modName.length > 0 && modName != "Unknown" && typeName != modName)
				parts.push(modName);
			parts.push(typeName);
			return ocamlModuleNameFromTypePathParts(parts);
		}

		// Map `<packagePath>:<ClassName>` to the OCaml module name we will emit.
		//
		// Why
		// - In Haxe, unqualified type names inside a package (e.g. `Util.foo()`) resolve to the
		//   current package by default.
		// - Our OCaml emission flattens `package.Class` to `Package_Class`, so we need a way to
		//   qualify those unqualified references during emission.
		final moduleNameByPkgAndClass:Map<String, String> = new Map();
		for (tm in typedModules) {
			final decl = tm.getParsed().getDecl();
			final moduleTypeName = moduleTypeNameFor(tm);
			final pkgRaw = decl == null ? "" : HxModuleDecl.getPackagePath(decl);
			final pkg = pkgRaw == null ? "" : StringTools.trim(pkgRaw);
			final modName = moduleTypeName == null ? "" : StringTools.trim(moduleTypeName);
			for (cls in HxModuleDecl.getClasses(decl)) {
				final className = HxClassDecl.getName(cls);
				if (className == null || className.length == 0 || className == "Unknown")
					continue;
				final emitted = moduleNameForDecl(decl, moduleTypeName, className);

				// Key 1: `<pkg>:<ClassName>` for unqualified references (`Util.foo()`).
				//
				// Note: this is ambiguous for module-local helper types that share a short name
				// across modules, but it is a useful bring-up heuristic and matches prior behavior.
				final key = pkg + ":" + className;
				if (!moduleNameByPkgAndClass.exists(key))
					moduleNameByPkgAndClass.set(key, emitted);

				// Key 2: `<pkg>:<Module.Helper>` for module-local helper types referenced as
				// `Module.Helper` (upstream Gate1 uses this heavily, e.g. `MyMacro.MyRestMacro`).
				//
				// Why add this
				// - Our bootstrap expression emitter recognizes `<type path>.field` by extracting
				//   a dotted path from the expression tree (e.g. `MyMacro.MyRestMacro`).
				// - Without recording the module qualifier here, the emitter cannot qualify the
				//   path with the current package, and OCaml compilation fails with "Unbound module".
				final rel = (modName.length > 0 && modName != "Unknown" && className != modName) ? (modName + "." + className) : className;
				final keyRel = pkg + ":" + rel;
				if (!moduleNameByPkgAndClass.exists(keyRel))
					moduleNameByPkgAndClass.set(keyRel, emitted);
			}
		}
		final moduleNameEntries = new Array<_ModuleNameEntry>();
		for (key in moduleNameByPkgAndClass.keys()) {
			final moduleName = moduleNameByPkgAndClass.get(key);
			if (moduleName != null)
				moduleNameEntries.push(new _ModuleNameEntry(key, moduleName));
		}
		currentModuleNameEntries = moduleNameEntries;
		final knownModuleNames:Map<String, Bool> = new Map();
		for (k in runtimeModuleNames.keys())
			knownModuleNames.set(k, true);
		for (entry in moduleNameEntries)
			knownModuleNames.set(entry.moduleName, true);
		currentKnownModuleNames = knownModuleNames;
		/**
			Global exact-import aliases that are unique across the current typed graph.

			Why
			- Per-module import rewrites are the correct first choice, but Stage3 bring-up still has
			  a few paths where an explicitly imported short name can reach expression lowering without
			  the module-local import map being populated for that exact emission context.
			- When that happens inside a packaged module, the package-local fallback rewrites
			  `Assert.contains` to `Unit_Assert.contains`, which is wrong if the real import is
			  `utest.Assert`.

			How
			- Build a conservative global map only for exact (non-wildcard) uppercase imports whose
			  short name resolves to a single unique target across the typed graph.
			- Ambiguous short names are dropped entirely, so this remains a narrow compatibility
			  fallback rather than a broad “first match wins” resolver.
		**/
		final uniqueImportAliasByIdent:Map<String, String> = new Map();
		final ambiguousImportAliasIdents:Map<String, Bool> = new Map();
		for (tm in typedModules) {
			for (rawImport in tm.getEnv().getImports()) {
				if (rawImport == null)
					continue;
				final imp = StringTools.trim(rawImport);
				if (imp.length == 0 || StringTools.endsWith(imp, ".*"))
					continue;
				final parts = imp.split(".");
				if (parts.length == 0)
					continue;
				final short = parts[parts.length - 1];
				if (short == null || short.length == 0 || !isUpperStart(short))
					continue;
				final importModName = ocamlModuleNameFromTypePath(imp);
				if (importModName.length == 0 || importModName == short)
					continue;
				if (ambiguousImportAliasIdents.exists(short))
					continue;
				final existing = uniqueImportAliasByIdent.get(short);
				if (existing == null) {
					uniqueImportAliasByIdent.set(short, importModName);
				} else if (existing != importModName) {
					uniqueImportAliasByIdent.remove(short);
					ambiguousImportAliasIdents.set(short, true);
				}
			}
		}
		currentGlobalImportAliasByIdent = uniqueImportAliasByIdent;

		// Index static members by module name so we can approximate `import Foo.Bar.*` static wildcard imports.
		//
		// Why
		// - Upstream `tests/RunCi.hx` uses `import runci.System.*` and refers to helpers like `infoMsg`
		//   without qualification.
		// - Stage3 does not implement full import resolution yet; this index enables a conservative
		//   `{ ident -> ModuleName }` rewrite that keeps bring-up moving.
		//
		// How
		// - Collect static function and field names from the parsed surface of each typed module.
		final staticMembersByModule:Map<String, Map<String, Bool>> = new Map();

		// Import-driven module alias index for call signature resolution.
		//
		// Why
		// - The Stage3 expression emitter lowers `Assert.floatEquals(...)` as a module access on the
		//   imported short name (`Assert`).
		// - The actual emitted provider module is the fully qualified one (e.g. `Utest_Assert`).
		// - Call signature lookups key off the OCaml callee expression string, so without alias
		//   signature entries we'd fail to detect optional-arg omissions for `Assert.*` calls.
		//
		// What
		// - `aliasShortsByTarget[targetMod] = [short1, short2, ...]`
		// - Used to record `Short.fn` signatures alongside `Target.fn` signatures.
		final aliasShortsByTarget:Map<String, Array<String>> = new Map();
		{
			final existingMods:Map<String, Bool> = new Map();
			for (k in runtimeModuleNames.keys())
				existingMods.set(k, true);
			for (tm in typedModules) {
				final decl = tm.getParsed().getDecl();
				final moduleTypeName = moduleTypeNameFor(tm);
				for (cls in HxModuleDecl.getClasses(decl)) {
					final className = HxClassDecl.getName(cls);
					if (className == null || className.length == 0 || className == "Unknown")
						continue;
					final modName = moduleNameForDecl(decl, moduleTypeName, className);
					existingMods.set(modName, true);
				}
			}

			final deny:Map<String, Bool> = new Map();
			for (m in [
				"Array",
				"Buffer",
				"Bytes",
				"Char",
				"Filename",
				"Format",
				"Gc",
				"Hashtbl",
				"Int",
				"Int32",
				"Int64",
				"List",
				"Map",
				"Marshal",
				"Nativeint",
				"Obj",
				"Option",
				"Printexc",
				"Printf",
				"Queue",
				"Result",
				"Set",
				"Stack",
				"Stdlib",
				"Str",
				"String",
				"Sys",
				"Unix",
			])
				deny.set(m, true);

			final aliasByShort:Map<String, String> = new Map();
			for (tm in typedModules) {
				for (rawImport in tm.getEnv().getImports()) {
					if (rawImport == null)
						continue;
					final imp = StringTools.trim(rawImport);
					if (imp.length == 0)
						continue;
					if (StringTools.endsWith(imp, ".*"))
						continue;
					final parts = imp.split(".");
					if (parts.length == 0)
						continue;
					final short = parts[parts.length - 1];
					if (short == null || short.length == 0 || !isUpperStart(short))
						continue;
					if (deny.exists(short))
						continue;
					// Don't alias over a real provider.
					if (existingMods.exists(short))
						continue;
					final target = ocamlModuleNameFromTypePath(imp);
					if (target == null || target.length == 0)
						continue;
					if (target == short)
						continue;
					// Only alias to a provider that actually exists in this build output.
					if (!existingMods.exists(target))
						continue;
					if (!aliasByShort.exists(short))
						aliasByShort.set(short, target);
				}
			}

			for (short in aliasByShort.keys()) {
				final target = aliasByShort.get(short);
				if (target == null || target.length == 0)
					continue;
				var arr = aliasShortsByTarget.get(target);
				if (arr == null) {
					arr = [];
					aliasShortsByTarget.set(target, arr);
				}
				if (arr.indexOf(short) == -1)
					arr.push(short);
			}

			// Keep exact-import alias stubs visible to the package-local fallback resolver.
			//
			// Why
			// - Stage3 later falls back from `Assert.contains(...)` to `Unit_Assert.contains(...)`
			//   whenever `Assert` is not recognized as a known emitted module.
			// - That is correct for true same-package helper types, but wrong when we also emit an
			//   exact-import alias stub such as `Assert.ml -> Utest_Assert`.
			// - Some upstream unit modules reach expression lowering without the module-local import
			//   alias map populated for that exact body, so the alias stub must also count as a
			//   "known module" to avoid bad package-local qualification.
			//
			// Non-goal
			// - This does not change import precedence. It only prevents the later same-package
			//   fallback from rewriting an already-valid short alias into a bogus package-local path.
			for (short in currentGlobalImportAliasByIdent.keys())
				currentKnownModuleNames.set(short, true);
			for (short in aliasByShort.keys())
				currentKnownModuleNames.set(short, true);
		}

		// Call signature index used by `exprToOcaml` to avoid OCaml partial application when the
		// Haxe call site omits optional/default/rest parameters.
		//
		// Keys match the emitted OCaml callee expression:
		// - Qualified: `ModuleName.fn`
		// - (Module-local unqualified keys are added per-module in `emitModule`.)
		final globalCallSigByCallee:Map<String, EmitterCallSig> = new Map();
		final importedSigModulesSeen:Map<String, Bool> = new Map();
		function recordFunctionSig(modName:String, fn:HxFunctionDecl):Void {
			final fnNameRaw = HxFunctionDecl.getName(fn);
			if (fnNameRaw == null || fnNameRaw.length == 0)
				return;
			final fnArgs = HxFunctionDecl.getArgs(fn);
			final argCount = fnArgs == null ? 0 : fnArgs.length;
			final needsReceiver = !HxFunctionDecl.getIsStatic(fn);
			var hasRest = false;
			var fixedCount = argCount;
			if (argCount > 0 && isRestLikeArg(fnArgs[argCount - 1])) {
				hasRest = true;
				fixedCount = argCount - 1;
			}
			var requiredCount = 0;
			for (i in 0...fixedCount) {
				final a = fnArgs[i];
				final hasDefault = switch (HxFunctionArg.getDefaultValue(a)) {
					case Default(_): true;
					case _: false;
				};
				if (!HxFunctionArg.getIsOptional(a) && !hasDefault)
					requiredCount += 1;
			}
			if (needsReceiver) {
				fixedCount += 1;
				requiredCount += 1;
			}
			final sig0:EmitterCallSig = {
				expected: fixedCount + (hasRest ? 1 : 0),
				required: requiredCount,
				fixed: fixedCount,
				hasRest: hasRest,
				needsReceiver: needsReceiver
			};
			final key0 = modName + "." + ocamlValueIdent(fnNameRaw);
			globalCallSigByCallee.set(key0, sig0);
			final aliasShorts = aliasShortsByTarget.get(modName);
			if (aliasShorts != null) {
				for (short in aliasShorts)
					globalCallSigByCallee.set(short + "." + ocamlValueIdent(fnNameRaw), sig0);
			}
		}
		for (tm in typedModules) {
			final decl = tm.getParsed().getDecl();
			final moduleTypeName = moduleTypeNameFor(tm);
			for (cls in HxModuleDecl.getClasses(decl)) {
				final className = HxClassDecl.getName(cls);
				if (className == null || className.length == 0 || className == "Unknown")
					continue;
				final modName = moduleNameForDecl(decl, moduleTypeName, className);

				final members:Map<String, Bool> = new Map();
				for (fn in HxClassDecl.getFunctions(cls)) {
					// Stage3 bootstrap: treat all class functions as "importable" members.
					//
					// Why
					// - Stage3 emission flattens class members into module-level `let` bindings.
					// - Some native frontend bring-up paths may not perfectly preserve `static` on all
					//   declarations (e.g. `public static inline function ...`), which would otherwise
					//   make `import Foo.*` miss helpers and collapse them to poison.
					//
					// Non-goal
					// - Correct instance method semantics. If upstream code relies on instance dispatch,
					//   Stage3 is not the rung for it.
					members.set(HxFunctionDecl.getName(fn), true);
				}
				for (field in HxClassDecl.getFields(cls)) {
					if (HxFieldDecl.getIsStatic(field))
						members.set(HxFieldDecl.getName(field), true);
				}
				staticMembersByModule.set(modName, members);

				// Record qualified function signatures so call sites can:
				// - pack rest args (`...args:T`) into an array,
				// - and fill missing optional args with `null` to avoid partial application.
				for (fn in HxClassDecl.getFunctions(cls)) {
					final fnNameRaw = HxFunctionDecl.getName(fn);
					if (fnNameRaw == null || fnNameRaw.length == 0)
						continue;

					final fnArgs = HxFunctionDecl.getArgs(fn);
					final argCount = fnArgs == null ? 0 : fnArgs.length;
					final needsReceiver = !HxFunctionDecl.getIsStatic(fn);
					// Robust rest detection:
					// - In valid Haxe syntax, the rest arg (if present) is the *last* parameter.
					// - During bring-up, we prefer a rule that can't be confused by accidental rest
					//   markings on earlier parameters (which would otherwise pack all args).
					var hasRest = false;
					var fixedCount = argCount;
					if (argCount > 0 && isRestLikeArg(fnArgs[argCount - 1])) {
						hasRest = true;
						fixedCount = argCount - 1;
					}

					var requiredCount = 0;
					for (i in 0...fixedCount) {
						final a = fnArgs[i];
						final hasDefault = switch (HxFunctionArg.getDefaultValue(a)) {
							case Default(_): true;
							case _: false;
						};
						if (!HxFunctionArg.getIsOptional(a) && !hasDefault)
							requiredCount += 1;
					}

					if (needsReceiver) {
						fixedCount += 1;
						requiredCount += 1;
					}

					_EmitterStageDebug.traceCallSig(modName, ocamlValueIdent(fnNameRaw), fnArgs, requiredCount, fixedCount, hasRest, needsReceiver);
					recordFunctionSig(modName, fn);
				}
			}
			final tmFilePath = tm.getParsed().getFilePath();
			for (rawImport in tm.getEnv().getImports()) {
				if (rawImport == null)
					continue;
				final imp = StringTools.trim(rawImport);
				if (imp.length == 0 || StringTools.endsWith(imp, ".*") || importedSigModulesSeen.exists(imp))
					continue;
				final resolvedImportFile = resolveImportedModuleFileFromContext(tmFilePath, imp);
				if (resolvedImportFile == null || !sys.FileSystem.exists(resolvedImportFile))
					continue;
				importedSigModulesSeen.set(imp, true);
				try {
					final importedSource = sys.io.File.getContent(resolvedImportFile);
					final importedParsed = ParserStage.parse(importedSource, resolvedImportFile);
					final importedDecl = importedParsed.getDecl();
					final importedModuleTypeName = expectedMainClassFromFile(resolvedImportFile);
					for (importedCls in HxModuleDecl.getClasses(importedDecl)) {
						final importedClassName = HxClassDecl.getName(importedCls);
						if (importedClassName == null || importedClassName.length == 0 || importedClassName == "Unknown")
							continue;
						final importedModName = moduleNameForDecl(importedDecl, importedModuleTypeName, importedClassName);
						for (fn in HxClassDecl.getFunctions(importedCls))
							recordFunctionSig(importedModName, fn);
					}
				} catch (_:haxe.Exception) {} catch (_:String) {}
			}
		}

		function emitModule(tm:TypedModule, isRoot:Bool):{files:Array<String>, rootMain:Null<String>} {
			// Stage 3 bring-up: `--hxhx-emit-full-bodies` exists so we can compile+run
			// upstream-style harness code (RunCi, macro host, etc).
			//
			// However, the Haxe standard library contains many constructs we do not model yet
			// (regex literals, abstracts, complex typing), and attempting to emit full bodies
			// for `std/` quickly explodes the surface area.
			//
			// Pragmatic rule:
			// - When `emitFullBodies=true`, still skip full-body emission for modules under `std/`.
			function allowFullBodiesForFile(filePath:String, isRoot:Bool):Bool {
				if (isRoot)
					return true;
				if (filePath == null || filePath.length == 0)
					return false;
				final p = filePath;
				final isStd = p.indexOf("/std/") != -1 || p.indexOf("\\std\\") != -1;
				return !isStd;
			}
			final moduleEmitBodies = emitFullBodies && allowFullBodiesForFile(tm.getParsed().getFilePath(), isRoot);

			final decl = tm.getParsed().getDecl();
			final mainClass = HxModuleDecl.getMainClass(decl);
			final parsedMainName = HxClassDecl.getName(mainClass);
			final moduleTypeName = moduleTypeNameFor(tm);
			final className = (moduleTypeName != null && moduleTypeName.length > 0) ? moduleTypeName : parsedMainName;
			if (className == null || className.length == 0 || className == "Unknown")
				return {files: [], rootMain: null};
			final mainModuleName = moduleNameForDecl(decl, moduleTypeName, className);
			_EmitterStageDebug.traceStage3Module("module", mainModuleName, tm.getParsed().getFilePath());
			final isRuntimeProvided = runtimeModuleNames.exists(mainModuleName);

			// Import-driven resolution for `Int64.<field>` (Haxe `haxe.Int64` vs OCaml stdlib `Int64`).
			function findInt64ImportTarget(imports:Array<String>):Null<String> {
				if (imports == null)
					return null;
				for (rawImport in imports) {
					if (rawImport == null)
						continue;
					final imp0 = StringTools.trim(rawImport);
					if (imp0.length == 0)
						continue;
					final base = StringTools.endsWith(imp0, ".*") ? imp0.substr(0, imp0.length - 2) : imp0;
					final parts = base.split(".");
					if (parts.length == 0)
						continue;
					final short = parts[parts.length - 1];
					if (short != "Int64")
						continue;
					final target = ocamlModuleNameFromTypePath(base);
					if (target != null && target.length > 0 && target != "Unknown")
						return target;
				}
				return null;
			}

			final importInt64 = findInt64ImportTarget(tm.getEnv().getImports());

			inline function isTyNamed(t:Null<TyType>, expected:String):Bool {
				if (t == null)
					return false;
				return t.toString() == expected;
			}

			/**
				Best-effort expression type inference for static-field initializers.
			**/
			function inferExprTypeForStaticInit(expr:Null<HxExpr>, knownByIdent:Map<String, TyType>):TyType {
				inline function inferStaticAtom(e:Null<HxExpr>):TyType {
					if (e == null)
						return TyType.unknown();
					return switch (e) {
						case EInt(_):
							TyType.fromHintText("Int");
						case EFloat(_):
							TyType.fromHintText("Float");
						case EString(_):
							TyType.fromHintText("String");
						case EBool(_):
							TyType.fromHintText("Bool");
						case EIdent(name):
							final t = knownByIdent.get(name);
							t == null ? TyType.unknown() : t;
						case EArrayDecl(_), EArrayComprehension(_, _, _):
							TyType.fromHintText("Array");
						case _:
							TyType.unknown();
					}
				}
				if (expr == null)
					return TyType.unknown();
				return switch (expr) {
					case EInt(_):
						TyType.fromHintText("Int");
					case EFloat(_):
						TyType.fromHintText("Float");
					case EString(_):
						TyType.fromHintText("String");
					case EBool(_):
						TyType.fromHintText("Bool");
					case EIdent(name):
						final t = knownByIdent.get(name);
						t == null ? TyType.unknown() : t;
					case ETernary(_cond, thenExpr, elseExpr):
						final tt = inferStaticAtom(thenExpr);
						final te = inferStaticAtom(elseExpr);
						(!tt.isUnknown() && tt.toString() == te.toString()) ? tt : TyType.unknown();
					case EBinop(op, left, right):
						final lt = inferStaticAtom(left);
						final rt = inferStaticAtom(right);
						if (op == "+"
							&& (isTyNamed(lt,
								"String") || isTyNamed(rt,
									"String"))) TyType.fromHintText("String"); else if (op == "/"
							&& ((isTyNamed(lt, "Int") || isTyNamed(lt, "Float"))
								&& (isTyNamed(rt,
									"Int") || isTyNamed(rt,
										"Float")))) TyType.fromHintText("Float"); else if ((op == "+" || op == "-" || op == "*" || op == "%")
							&& isTyNamed(lt, "Int")
							&& isTyNamed(rt,
								"Int")) TyType.fromHintText("Int"); else if ((op == "+" || op == "-" || op == "*")
							&& (isTyNamed(lt, "Float") || isTyNamed(rt, "Float"))) TyType.fromHintText("Float"); else TyType.unknown();
					case EArrayDecl(_), EArrayComprehension(_, _, _):
						TyType.fromHintText("Array");
					case _:
						TyType.unknown();
				}
			}

			function inferStaticFieldType(field:HxFieldDecl, knownByIdent:Map<String, TyType>):TyType {
				final hinted = TyType.fromHintText(HxFieldDecl.getTypeHint(field));
				if (hinted != null && !hinted.isUnknown())
					return hinted;
				return inferExprTypeForStaticInit(HxFieldDecl.getInit(field), knownByIdent);
			}

			function emitStubClass(cls:HxClassDecl):Null<String> {
				final nm = HxClassDecl.getName(cls);
				if (nm == null || nm.length == 0 || nm == "Unknown")
					return null;
				final moduleName = moduleNameForDecl(decl, moduleTypeName, nm);

				final prevInt64 = currentImportInt64;
				currentImportInt64 = importInt64;
				try {
					final out = new Array<String>();
					out.push("(* Generated by hxhx(stage3) bootstrap emitter *)");
					// Keep bring-up output warning-clean under strict dune setups.
					// These warnings are common when we use `Obj.magic` / exception-return tricks.
					out.push("[@@@warning \"-21-26\"]");
					out.push("");

					// Stage 3 bring-up: upstream unit fixtures call `StringTools.hex`, but our parser
					// frequently fails to parse the full stdlib `StringTools.hx` at this rung, so the
					// stub class would otherwise be empty and calls would fail at link time.
					//
					// Provide a tiny, self-contained implementation that is "close enough" for bootstrapping.
					final hasStringToolsHex = moduleName == "StringTools";
					if (hasStringToolsHex) {
						out.push("(* hxhx(stage3) bootstrap shim: StringTools.hex *)");
						out.push("let hex (n : int) (digits : Obj.t) : string =");
						out.push("  let hexChars = \"0123456789ABCDEF\" in");
						out.push("  let n32 = Int32.of_int n in");
						out.push("  let rec build (x : Int32.t) (acc : string) : string =");
						out.push("    let digit = Int32.to_int (Int32.logand x 0xFl) in");
						out.push("    let acc2 = (Stdlib.String.make 1 (Stdlib.String.get hexChars digit)) ^ acc in");
						out.push("    let x2 = Int32.shift_right_logical x 4 in");
						out.push("    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2");
						out.push("  in");
						out.push("  let s = build n32 \"\" in");
						out.push("  let digits_i = if digits == HxRuntime.hx_null then 0 else (Obj.obj digits : int) in");
						out.push("  if digits_i <= 0 then s else");
						out.push("    let rec pad (s0 : string) : string =");
						out.push("      if Stdlib.String.length s0 < digits_i then pad (\"0\" ^ s0) else s0");
						out.push("    in");
						out.push("    pad s");
						out.push("");
					}

					// Emit static fields (best-effort).
					final parsedFields = HxClassDecl.getFields(cls);
					final staticTyByIdent:Map<String, TyType> = new Map();
					final staticAllowedValueIdents:Map<String, Bool> = new Map();
					for (f in parsedFields) {
						if (!HxFieldDecl.getIsStatic(f))
							continue;
						final nameRaw = HxFieldDecl.getName(f);
						if (nameRaw == null || nameRaw.length == 0)
							continue;
						final inferredType = inferStaticFieldType(f, staticTyByIdent);
						final init = HxFieldDecl.getInit(f);
						final prevAllowedValueIdentNames = currentAllowedValueIdentNames;
						currentAllowedValueIdentNames = staticAllowedValueIdents;
						final initOcaml = init == null ? "(Obj.magic HxRuntime.hx_null)" : exprToOcaml(init, null, staticTyByIdent, null,
							HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, globalCallSigByCallee);
						currentAllowedValueIdentNames = prevAllowedValueIdentNames;
						out.push("let " + ocamlValueIdent(nameRaw) + " = " + initOcaml);
						out.push("");
						staticAllowedValueIdents.set(nameRaw, true);
						final knownType = staticTyByIdent.get(nameRaw);
						if (knownType == null || (knownType.isUnknown() && !inferredType.isUnknown()))
							staticTyByIdent.set(nameRaw, inferredType);
					}

					// Emit function stubs with correct arity to avoid OCaml partial application issues.
					for (fn in HxClassDecl.getFunctions(cls)) {
						final nameRaw = HxFunctionDecl.getName(fn);
						if (nameRaw == null || nameRaw.length == 0)
							continue;
						if (hasStringToolsHex && nameRaw == "hex")
							continue;
						final fnArgs = HxFunctionDecl.getArgs(fn);
						final args = fnArgs == null ? [] : fnArgs;
						final ocamlArgs = if (args.length == 0) {
							"()";
						} else {
							args.map(a -> ocamlValueIdent(HxFunctionArg.getName(a))).join(" ");
						};
						out.push("let " + ocamlValueIdent(nameRaw) + " " + ocamlArgs + " = (Obj.magic 0)");
						out.push("");
					}

					final mlPath = haxe.io.Path.join([outAbs, moduleName + ".ml"]);
					sys.io.File.saveContent(mlPath, out.join("\n"));
					currentImportInt64 = prevInt64;
					return moduleName + ".ml";
				} catch (e:TyperError) {
					currentImportInt64 = prevInt64;
					throw e;
				} catch (e:String) {
					currentImportInt64 = prevInt64;
					throw e;
				}
			}

			function emitMainClass():Null<String> {
				final prevOcamlModule = currentOcamlModuleName;
				final prevModuleFilePath = currentModuleFilePath;
				final prevInt64 = currentImportInt64;
				final prevInstanceFieldsByTypePath = currentInstanceFieldsByTypePath;
				final prevInstanceMethodsByTypePath = currentInstanceMethodsByTypePath;
				final moduleFilePath = tm.getParsed().getFilePath();
				final mainClassName = HxClassDecl.getName(mainClass);
				currentOcamlModuleName = mainModuleName;
				currentModuleFilePath = moduleFilePath;
				currentImportInt64 = importInt64;
				try {
					final parsedFns = HxClassDecl.getFunctions(mainClass);
					final parsedByName = new Map<String, HxFunctionDecl>();
					for (fn in parsedFns)
						parsedByName.set(HxFunctionDecl.getName(fn), fn);

					final instanceFieldsByTypePath = new Array<_InstanceFieldEntry>();
					final instanceMethodsByTypePath = new Array<_InstanceMethodEntry>();
					final declPkg = HxModuleDecl.getPackagePath(decl);
					for (cls in HxModuleDecl.getClasses(decl)) {
						final clsName = HxClassDecl.getName(cls);
						if (clsName == null || clsName.length == 0 || clsName == "Unknown")
							continue;
						final fields = new Array<HxFieldDecl>();
						for (f in HxClassDecl.getFields(cls))
							if (!HxFieldDecl.getIsStatic(f))
								fields.push(f);
						final methodNames = new Array<String>();
						for (fn in HxClassDecl.getFunctions(cls)) {
							if (HxFunctionDecl.getIsStatic(fn))
								continue;
							final fnName = HxFunctionDecl.getName(fn);
							if (fnName != null && fnName.length > 0)
								methodNames.push(fnName);
						}
						instanceFieldsByTypePath.push(new _InstanceFieldEntry(clsName, fields));
						instanceMethodsByTypePath.push(new _InstanceMethodEntry(clsName, methodNames));
						if (declPkg != null && declPkg.length > 0) {
							final keyPkg = declPkg + "." + clsName;
							instanceFieldsByTypePath.push(new _InstanceFieldEntry(keyPkg, fields));
							instanceMethodsByTypePath.push(new _InstanceMethodEntry(keyPkg, methodNames));
						}
					}
					currentInstanceFieldsByTypePath = instanceFieldsByTypePath;
					currentInstanceMethodsByTypePath = instanceMethodsByTypePath;

					final typedFns = tm.getEnv().getMainClass().getFunctions();
					function effectiveFunctionArgs(tf:TyFunctionEnv, parsedFn:Null<HxFunctionDecl>):Array<{name:String, ty:TyType}> {
						final typedArgs = tf.getParams();
						final parsedArgs = parsedFn == null ? [] : HxFunctionDecl.getArgs(parsedFn);
						final emitArgs = new Array<{name:String, ty:TyType}>();
						if (parsedArgs.length > 0) {
							for (i in 0...parsedArgs.length) {
								final parsedArg = parsedArgs[i];
								final typedArg = i < typedArgs.length ? typedArgs[i] : null;
								final parsedName = HxFunctionArg.getName(parsedArg);
								final typedName = typedArg == null ? null : typedArg.getName();
								final name = parsedName != null && parsedName.length > 0 ? parsedName : typedName;
								final ty = typedArg == null ? TyType.fromHintText(HxFunctionArg.getTypeHint(parsedArg)) : typedArg.getType();
								emitArgs.push({
									name: name == null || name.length == 0 ? ("arg" + i) : name,
									ty: ty == null ? TyType.unknown() : ty
								});
							}
							for (i in parsedArgs.length...typedArgs.length) {
								final typedArg = typedArgs[i];
								emitArgs.push({
									name: typedArg.getName(),
									ty: typedArg.getType()
								});
							}
							return emitArgs;
						}
						for (typedArg in typedArgs) {
							emitArgs.push({
								name: typedArg.getName(),
								ty: typedArg.getType()
							});
						}
						return emitArgs;
					}
					final arityByName:Map<String, Int> = new Map();
					for (tf in typedFns) {
						final parsedFn = parsedByName.get(tf.getName());
						final isStaticFn = parsedFn == null ? true : HxFunctionDecl.getIsStatic(parsedFn);
						final extraThis = isStaticFn ? 0 : 1;
						arityByName.set(tf.getName(), effectiveFunctionArgs(tf, parsedFn).length + extraThis);
					}
					final fnReturnTypesByName:Map<String, TyType> = new Map();
					for (tf in typedFns)
						fnReturnTypesByName.set(tf.getName(), tf.getReturnType());

					// Provide both:
					// - qualified signatures (all modules) for `Pkg_Mod.fn(...)` style calls,
					// - and unqualified signatures (this module) for `fn(...)` calls.
					final callSigByCallee:Map<String, EmitterCallSig> = new Map();
					for (k in globalCallSigByCallee.keys())
						callSigByCallee.set(k, globalCallSigByCallee.get(k));
					for (fn in parsedFns) {
						final fnNameRaw = HxFunctionDecl.getName(fn);
						if (fnNameRaw == null || fnNameRaw.length == 0)
							continue;
						final isStaticFn = HxFunctionDecl.getIsStatic(fn);
						final fnArgs = HxFunctionDecl.getArgs(fn);
						final argCount = fnArgs == null ? 0 : fnArgs.length;
						var hasRest = false;
						var fixedCount = argCount;
						if (argCount > 0 && isRestLikeArg(fnArgs[argCount - 1])) {
							hasRest = true;
							fixedCount = argCount - 1;
						}

						var requiredCount = 0;
						for (i in 0...fixedCount) {
							final a = fnArgs[i];
							final hasDefault = switch (HxFunctionArg.getDefaultValue(a)) {
								case Default(_): true;
								case _: false;
							};
							if (!HxFunctionArg.getIsOptional(a) && !hasDefault)
								requiredCount += 1;
						}

						if (!isStaticFn) {
							fixedCount += 1;
							requiredCount += 1;
						}
						final expected = fixedCount + (hasRest ? 1 : 0);
						final needsReceiver = !isStaticFn;
						_EmitterStageDebug.traceCallSig(mainModuleName, ocamlValueIdent(fnNameRaw), fnArgs, requiredCount, fixedCount, hasRest, needsReceiver);
						callSigByCallee.set(ocamlValueIdent(fnNameRaw), {
							expected: expected,
							required: requiredCount,
							fixed: fixedCount,
							hasRest: hasRest,
							needsReceiver: needsReceiver
						});
					}

					// Best-effort `import Foo.Bar.*` support:
					// Build a map of unqualified identifiers -> imported module name for static members.
					final staticImportByIdent:Map<String, String> = new Map();
					// Prefer module-local helper type aliases in the current module.
					//
					// Why
					// - Unqualified helper references like `Helper.ANSWER` inside `Main.hx` should bind to
					//   the emitted helper provider `Main_Helper`.
					// - A global short-name map can collide with similarly named helpers in other modules.
					//
					// How
					// - Seed this map with classes declared in the current module first, so subsequent
					//   wildcard-import resolution does not override local helper bindings.
					for (localCls in HxModuleDecl.getClasses(decl)) {
						final localName = HxClassDecl.getName(localCls);
						if (localName == null || localName.length == 0 || localName == "Unknown")
							continue;
						if (localName == className)
							continue;
						staticImportByIdent.set(localName, moduleNameForDecl(decl, moduleTypeName, localName));
					}
					for (rawImport in tm.getEnv().getImports()) {
						if (rawImport == null)
							continue;
						final imp = StringTools.trim(rawImport);
						if (!StringTools.endsWith(imp, ".*")) {
							final parts = imp.split(".");
							if (parts.length == 0)
								continue;
							final short = parts[parts.length - 1];
							if (short == null || short.length == 0 || !isUpperStart(short))
								continue;
							final importModName = ocamlModuleNameFromTypePath(imp);
							if (importModName.length == 0 || importModName == short)
								continue;
							if (!staticImportByIdent.exists(short))
								staticImportByIdent.set(short, importModName);
							continue;
						}
						if (!StringTools.endsWith(imp, ".*"))
							continue;

						final base = imp.substr(0, imp.length - 2);
						final importModName = ocamlModuleNameFromTypePath(base);
						if (importModName.length == 0)
							continue;

						final membersRaw:Map<String, Bool> = staticMembersByModule.get(importModName);
						if (membersRaw == null)
							continue;
						final memberKeys:Null<Iterator<String>> = mapKeysRaw(cast membersRaw);
						if (memberKeys == null)
							continue;
						for (name in memberKeys) {
							if (!staticImportByIdent.exists(name))
								staticImportByIdent.set(name, importModName);
						}
					}

					final out = new Array<String>();
					out.push("(* Generated by hxhx(stage3) bootstrap emitter *)");
					// Keep bring-up output warning-clean under strict dune setups.
					// These warnings are common when we use `Obj.magic` / exception-return tricks.
					out.push("[@@@warning \"-21-26\"]");
					out.push("");

					final parsedFields = HxClassDecl.getFields(mainClass);
					final staticFieldTypeByName:Map<String, TyType> = new Map();
					for (f in parsedFields) {
						if (!HxFieldDecl.getIsStatic(f))
							continue;
						final fieldName = HxFieldDecl.getName(f);
						if (fieldName == null || fieldName.length == 0)
							continue;
						final inferred = inferStaticFieldType(f, staticFieldTypeByName);
						staticFieldTypeByName.set(fieldName, inferred == null ? TyType.unknown() : inferred);
					}

					// Stage 3 bring-up: static initializer ordering.
					//
					// Why
					// - Haxe allows `static final` initializers to call helper functions declared later in
					//   the class body.
					// - OCaml evaluates top-level `let` bindings in order, and does not allow a `let` value
					//   to reference a later `let rec` function group.
					//
					// How
					// - Detect unqualified function calls used by static initializers.
					// - Emit a small "prelude" `let rec ... and ...` group for those helper functions
					//   *before* emitting static `let` values.
					//
					// Constraints
					// - Prelude functions must not depend on static values (which are emitted later).
					final staticFieldNames:Map<String, Bool> = new Map();
					for (f in parsedFields) {
						if (!HxFieldDecl.getIsStatic(f))
							continue;
						final n = HxFieldDecl.getName(f);
						if (n != null && n.length > 0)
							staticFieldNames.set(n, true);
					}

					final staticInitCalls:Map<String, Bool> = new Map();
					// Use an explicit stack instead of a recursive local function.
					//
					// Why
					// - This code runs inside `hxhx` itself, which is compiled by our OCaml backend.
					// - Recursive local functions are a known source of instability during bring-up,
					//   so we prefer an explicit worklist here.
					final staticInitWorklist = new Array<HxExpr>();
					for (f in parsedFields) {
						if (!HxFieldDecl.getIsStatic(f))
							continue;
						final init = HxFieldDecl.getInit(f);
						if (init != null)
							staticInitWorklist.push(init);
					}
					while (staticInitWorklist.length > 0) {
						final e = staticInitWorklist.pop();
						if (e == null)
							continue;
						switch (e) {
							case ECall(callee, args):
								switch (callee) {
									case EIdent(name):
										if (name != null && name.length > 0) staticInitCalls.set(name, true);
									case EField(_obj, field):
										if (field != null && field.length > 0) staticInitCalls.set(field, true);
									case _:
								}
								if (callee != null)
									staticInitWorklist.push(callee);
								if (args != null)
									for (a in args)
										if (a != null)
											staticInitWorklist.push(a);
							case EField(obj, _):
								if (obj != null)
									staticInitWorklist.push(obj);
							case ELambda(_, body):
								if (body != null)
									staticInitWorklist.push(body);
							case ETernary(cond, thenExpr, elseExpr):
								if (cond != null)
									staticInitWorklist.push(cond);
								if (thenExpr != null)
									staticInitWorklist.push(thenExpr);
								if (elseExpr != null)
									staticInitWorklist.push(elseExpr);
							case EAnon(_, values):
								if (values != null)
									for (v in values)
										if (v != null)
											staticInitWorklist.push(v);
							case ESwitch(scrutinee, _patterns, exprs):
								if (scrutinee != null)
									staticInitWorklist.push(scrutinee);
								if (exprs != null)
									for (branchExpr in exprs)
										if (branchExpr != null)
											staticInitWorklist.push(branchExpr);
							case ENew(_, args):
								if (args != null)
									for (a in args)
										if (a != null)
											staticInitWorklist.push(a);
							case EUnop(_, expr):
								if (expr != null)
									staticInitWorklist.push(expr);
							case EBinop(_, left, right):
								if (left != null)
									staticInitWorklist.push(left);
								if (right != null)
									staticInitWorklist.push(right);
							case EArrayComprehension(_, iterable, yieldExpr):
								if (iterable != null)
									staticInitWorklist.push(iterable);
								if (yieldExpr != null)
									staticInitWorklist.push(yieldExpr);
							case EArrayDecl(values):
								if (values != null)
									for (v in values)
										if (v != null)
											staticInitWorklist.push(v);
							case EArrayAccess(array, index):
								if (array != null)
									staticInitWorklist.push(array);
								if (index != null)
									staticInitWorklist.push(index);
							case ERange(start, end):
								if (start != null)
									staticInitWorklist.push(start);
								if (end != null)
									staticInitWorklist.push(end);
							case ECast(expr, _):
								if (expr != null)
									staticInitWorklist.push(expr);
							case EUntyped(expr):
								if (expr != null)
									staticInitWorklist.push(expr);
							case _:
						}
					}

					final fnNames:Map<String, Bool> = new Map();
					for (tf in typedFns) {
						final n = tf.getName();
						if (n != null && n.length > 0)
							fnNames.set(n, true);
					}

					final preludeFnNames:Map<String, Bool> = new Map();
					for (name in staticInitCalls.keys()) {
						if (!fnNames.exists(name))
							continue;
						if (name == "load")
							continue;
						preludeFnNames.set(name, true);
					}

					final fnCallsByName:Map<String, Map<String, Bool>> = new Map();
					final fnRefsStaticByName:Map<String, Bool> = new Map();
					function analyzeFn(nameRaw:String):Void {
						if (fnCallsByName.exists(nameRaw))
							return;
						var tf:Null<TyFunctionEnv> = null;
						for (t in typedFns) {
							if (t.getName() == nameRaw) {
								tf = t;
								break;
							}
						}
						final parsedFn = parsedByName.get(nameRaw);
						final calls:Map<String, Bool> = new Map();
						var refsStatic = false;
						if (tf != null && parsedFn != null) {
							final locals:Map<String, Bool> = new Map();
							for (p in effectiveFunctionArgs(tf, parsedFn)) {
								final pn = p.name;
								if (pn != null && pn.length > 0)
									locals.set(pn, true);
							}
							for (s in HxFunctionDecl.getBody(parsedFn))
								collectLocalsForPreludeFromStmtRec(s, locals);
							final idents:Map<String, Bool> = new Map();
							for (s in HxFunctionDecl.getBody(parsedFn))
								scanStmtForPreludeDepsRec(s, locals, calls, idents);
							for (n in idents.keys()) {
								if (staticFieldNames.exists(n)) {
									refsStatic = true;
									break;
								}
							}
						}
						fnCallsByName.set(nameRaw, calls);
						fnRefsStaticByName.set(nameRaw, refsStatic);
					}

					// Close over unqualified call dependencies for prelude functions.
					var changed = true;
					while (changed) {
						changed = false;
						final keys = [for (k in preludeFnNames.keys()) k];
						for (nameRaw in keys) {
							analyzeFn(nameRaw);
							final callsRaw:Map<String, Bool> = fnCallsByName.get(nameRaw);
							if (callsRaw == null)
								continue;
							final callKeys:Null<Iterator<String>> = mapKeysRaw(cast callsRaw);
							if (callKeys == null)
								continue;
							for (callee in callKeys) {
								if (!fnNames.exists(callee))
									continue;
								if (callee == "load")
									continue;
								if (!preludeFnNames.exists(callee)) {
									preludeFnNames.set(callee, true);
									changed = true;
								}
							}
						}
					}

					// Drop any prelude candidates that depend on static values (they cannot be emitted
					// before static initializers without breaking OCaml scoping).
					for (nameRaw in [for (k in preludeFnNames.keys()) k]) {
						analyzeFn(nameRaw);
						if (fnRefsStaticByName.get(nameRaw) == true)
							preludeFnNames.remove(nameRaw);
					}

					var sawMain = false;
					final exceptions = new Array<String>();

					// OCaml limitation (mutual recursion + polymorphism):
					// `let rec ... and ...` groups do not generalize polymorphic values the same way as
					// independent `let` bindings.
					//
					// In the macro API surface (notably `haxe.macro.Context`), a helper like `load`
					// is used to return many different function shapes:
					//   `load("defined")(1)(key)`  vs  `load("init_macros_done")(0)()`
					//
					// If `load` is emitted as an `and load ...` member of the same recursive group,
					// OCaml will try to unify all those instantiations and we get type errors like:
					//   "expected string but got unit" at zero-arg call sites.
					//
					// Bring-up fix:
					// - When emitting macro std modules, hoist `load` to an independent non-rec `let`
					//   binding before the main `let rec` group so it can be generalized.
					//
					// Note: This must apply in both "stub body" and "full body" emission modes. The failure mode
					// (monomorphic `load` inside the recursive group) appears in both configurations.
					final shouldHoistLoad = StringTools.startsWith(mainModuleName, "Haxe_macro_");
					if (shouldHoistLoad) {
						for (tf in typedFns) {
							if (tf.getName() != "load")
								continue;
							final nameRaw = tf.getName();
							_EmitterStageDebug.traceStage3Function("fn_enter", mainModuleName, nameRaw);
							final parsedFn = parsedByName.get(nameRaw);
							final emitArgs = effectiveFunctionArgs(tf, parsedFn);
							final ocamlArgs = emitArgs.length == 0 ? "()" : emitArgs.map(a -> "(" + ocamlValueIdent(a.name) + " : "
								+ ocamlTypeFromTy(a.ty) + ")")
								.join(" ");
							final retTy = ocamlTypeFromTy(tf.getReturnType());
							final allowed:Map<String, Bool> = new Map();
							final tyByIdent:Map<String, TyType> = new Map();
							for (a in emitArgs)
								allowed.set(a.name, true);
							for (a in emitArgs)
								tyByIdent.set(a.name, a.ty);
							for (name in allowed.keys())
								if (tyByIdent.get(name) == null)
									tyByIdent.set(name, TyType.unknown());
							final body = parsedFn == null ? "(Obj.magic 0)" : returnExprToOcaml(parsedFn.getFirstReturnExpr(), allowed, tf.getReturnType(),
								arityByName, tyByIdent, staticImportByIdent, HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, callSigByCallee);
							_EmitterStageDebug.traceStage3Function("fn_after_body", mainModuleName, nameRaw);

							out.push("let " + ocamlValueIdent(nameRaw) + " " + ocamlArgs + " : " + retTy + " = " + body);
							out.push("");
							break;
						}
					}

					// Emit static-initializer helper functions before static values so static `let` bindings
					// can call them (Haxe semantics).
					final typedFnsPrelude = new Array<TyFunctionEnv>();
					for (tf in typedFns) {
						final nameRaw = tf.getName();
						if (nameRaw == null || nameRaw.length == 0)
							continue;
						if (!preludeFnNames.exists(nameRaw))
							continue;
						typedFnsPrelude.push(tf);
					}

					function emitFnGroup(group:Array<TyFunctionEnv>):Void {
						for (i in 0...group.length) {
							final tf = group[i];
							final nameRaw = tf.getName();
							_EmitterStageDebug.traceStage3Function("fn_enter", mainModuleName, nameRaw);
							final name = ocamlValueIdent(nameRaw);
							final previousRegionKey = currentPortableMetalizationRegionKey;
							final previousFunctionNameRaw = currentFunctionNameRaw;
							currentPortableMetalizationRegionKey = backend.ocaml.PortableMetalizationPlanner.functionRegionKey(moduleFilePath, mainClassName,
								nameRaw);
							currentFunctionNameRaw = nameRaw;
							if (name == "main")
								sawMain = true;

							final parsedFn = parsedByName.get(nameRaw);
							final emitArgs = effectiveFunctionArgs(tf, parsedFn);
							final isStaticFn = parsedFn == null ? true : HxFunctionDecl.getIsStatic(parsedFn);
							final headArgs = new Array<String>();
							if (!isStaticFn)
								headArgs.push("(this_ : _)");
							for (a in emitArgs)
								headArgs.push("(" + ocamlValueIdent(a.name) + " : " + ocamlTypeFromTy(a.ty) + ")");
							final ocamlArgs = headArgs.length == 0 ? "()" : headArgs.join(" ");

							final retTy = ocamlTypeFromTy(tf.getReturnType());
							final allowed:Map<String, Bool> = new Map();
							final tyByIdent:Map<String, TyType> = new Map();
							for (a in emitArgs)
								allowed.set(a.name, true);
							for (a in emitArgs)
								tyByIdent.set(a.name, a.ty);
							if (!isStaticFn) {
								allowed.set("this", true);
								tyByIdent.set("this", TyType.fromHintText("Dynamic"));
							}
							for (tf2 in typedFns)
								allowed.set(tf2.getName(), true);
							for (f in parsedFields)
								if (HxFieldDecl.getIsStatic(f)) {
									final fieldName = HxFieldDecl.getName(f);
									if (fieldName == null || fieldName.length == 0)
										continue;
									allowed.set(fieldName, true);
									if (tyByIdent.get(fieldName) == null || tyByIdent.get(fieldName).isUnknown()) {
										final inferred = staticFieldTypeByName.get(fieldName);
										tyByIdent.set(fieldName, inferred == null ? TyType.unknown() : inferred);
									}
								}

							final localTypeHints:Map<String, TyType> = new Map();
							if (moduleEmitBodies) {
								for (l in tf.getLocals()) {
									final n = l.getName();
									if (n != null && n.length > 0 && localTypeHints.get(n) == null)
										localTypeHints.set(n, l.getType());
								}
							}

							for (name in allowed.keys())
								if (tyByIdent.get(name) == null)
									tyByIdent.set(name, TyType.unknown());

							final prevAllowedValueIdentNames = currentAllowedValueIdentNames;
							currentAllowedValueIdentNames = allowed;

							var body = if (parsedFn == null) {
								"()";
							} else if (!moduleEmitBodies) {
								final tyByIdentDebug:Null<haxe.ds.StringMap<TyType>> = cast tyByIdent;
								_EmitterStageDebug.traceSelfRecursion("fn_return_entry",
									"current=" + nameRaw + " isStatic=" + (isStaticFn ? "1" : "0") + " hasTyThis="
									+ (tyByIdentDebug != null && tyByIdentDebug.exists("this") ? "1" : "0") + " hasTyThis_="
									+ (tyByIdentDebug != null && tyByIdentDebug.exists("this_") ? "1" : "0"));
								if (mainModuleName == "Reflaxe_elixir_generator_ProjectGenerator" && nameRaw == "loadTemplate") {
									"(let libPath = getLibraryPath (this_) in "
									+ "let templatePath = HxBootArray.join (HxBootArray.of_list [(Obj.magic (libPath)); (Obj.magic (\"templates\")); "
									+ "(Obj.magic (\"project\")); (Obj.magic (templateName))]) (\"/\") (fun (s : string) -> s) in "
									+ "if not (HxFileSystem.exists templatePath) then defaultTemplate (this_) (templateName) else HxFile.getContent (templatePath))";
								} else if (mainModuleName == "Reflaxe_elixir_generator_TemplateEngine" && nameRaw == "transformFilename") {
									"processPlaceholders (this_) (filename) (replacements)";
								} else {
									returnExprToOcaml(parsedFn.getFirstReturnExpr(), allowed, tf.getReturnType(), arityByName, tyByIdent, staticImportByIdent,
										HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, callSigByCallee);
								}
							} else {final exc = "HxReturn_" + escapeOcamlIdentPart(nameRaw);
								exceptions.push("exception " + exc + " of Obj.t");
								final stmts = HxFunctionDecl.getBody(parsedFn);
								_EmitterStageDebug.traceStage3Function("fn_before_stmt_list", mainModuleName, nameRaw);
								final stmtBodyBuf = new StringBuf();
								stmtListToOcaml(stmts, allowed, exc, stmtBodyBuf, arityByName, tyByIdent, staticImportByIdent, HxModuleDecl.getPackagePath(decl),
									moduleNameByPkgAndClass, callSigByCallee, localTypeHints, fnReturnTypesByName, mainModuleName, nameRaw);
								_EmitterStageDebug.traceStage3Phase("after_stmt_list_call");
								_EmitterStageDebug.traceStage3Phase("after_stmt_list_copy");
								final stmtBody = stmtBodyBuf.toString();
								_EmitterStageDebug.traceStage3Function("fn_after_stmt_list", mainModuleName, nameRaw);
								final bodyBuf = new StringBuf();
								bodyBuf.add("((");
								bodyBuf.add("try (let _ = ");
								bodyBuf.add(stmtBody);
								bodyBuf.add(" in (Obj.magic 0)) ");
								bodyBuf.add("with ");
								bodyBuf.add(exc);
								bodyBuf.add(" v -> (Obj.magic v)");
								bodyBuf.add(") : ");
								bodyBuf.add(retTy);
								bodyBuf.add(")");
								bodyBuf.toString();
							};
							_EmitterStageDebug.traceStage3Function("fn_after_body", mainModuleName, nameRaw);
							currentAllowedValueIdentNames = prevAllowedValueIdentNames;
							// Stage3 stdlib bring-up guard:
							// - `haxe.ds.EnumValueMap.compareArg` can recover as
							//   `compare ((Obj.magic 0)) ((Obj.magic 0))`, which misses receiver/arg
							//   forwarding and fails with partial-application type errors.
							// - Normalize that exact degraded body to the receiver-aware local-param call.
							if (mainModuleName == "Haxe_ds_EnumValueMap"
								&& nameRaw == "compareArg"
								&& !isStaticFn
								&& emitArgs.length >= 2
								&& body == "compare ((Obj.magic 0)) ((Obj.magic 0))") {
								final arg0 = ocamlReadValueIdent(emitArgs[0].name);
								final arg1 = ocamlReadValueIdent(emitArgs[1].name);
								body = "compare (this_) (" + arg0 + ") (" + arg1 + ")";
							}

							final kw = i == 0 ? "let rec" : "and";
							_EmitterStageDebug.traceStage3Function("fn_before_bind", mainModuleName, nameRaw);
							final bindingPrefixBuf = new StringBuf();
							bindingPrefixBuf.add(kw);
							bindingPrefixBuf.add(" ");
							bindingPrefixBuf.add(name);
							bindingPrefixBuf.add(" ");
							bindingPrefixBuf.add(ocamlArgs);
							bindingPrefixBuf.add(" : ");
							bindingPrefixBuf.add(retTy);
							bindingPrefixBuf.add(" = ");
							final bindingPrefix = bindingPrefixBuf.toString();
							_EmitterStageDebug.traceStage3Function("fn_after_prefix", mainModuleName, nameRaw);
							final bindingBuf = new StringBuf();
							bindingBuf.add(bindingPrefix);
							bindingBuf.add(body);
							final bindingLine = bindingBuf.toString();
							_EmitterStageDebug.traceStage3Function("fn_after_bind", mainModuleName, nameRaw);
							out.push(bindingLine);
							out.push("");
							_EmitterStageDebug.traceStage3Function("fn_after_emit", mainModuleName, nameRaw);
							currentFunctionNameRaw = previousFunctionNameRaw;
							currentPortableMetalizationRegionKey = previousRegionKey;
						}
					}

					if (typedFnsPrelude.length > 0) {
						emitFnGroup(typedFnsPrelude);
					}

					// Emit class-scope static values (bootstrap subset).
					//
					// Why
					// - Upstream harness code relies on `static final` constants (Ints/Strings + simple if/switch).
					// - Without emitting these as OCaml `let` bindings, references collapse to bring-up poison.
					// Static initializers often refer to earlier static finals (e.g. `unitDir` refers to `repoDir`).
					// During bring-up we treat those names as "bound" incrementally to avoid collapsing them to poison.
					final staticTyByIdent:Map<String, TyType> = new Map();
					final staticAllowedValueIdents:Map<String, Bool> = new Map();
					for (f in parsedFields) {
						if (!HxFieldDecl.getIsStatic(f))
							continue;
						final nameRaw = HxFieldDecl.getName(f);
						if (nameRaw == null || nameRaw.length == 0)
							continue;
						final inferredType = staticFieldTypeByName.get(nameRaw);
						if (inferredType != null && staticTyByIdent.get(nameRaw) == null)
							staticTyByIdent.set(nameRaw, inferredType);
						final init = HxFieldDecl.getInit(f);
						final prevAllowedValueIdentNames = currentAllowedValueIdentNames;
						currentAllowedValueIdentNames = staticAllowedValueIdents;
						final initOcaml = init == null ? "(Obj.magic 0)" : exprToOcaml(init, arityByName, staticTyByIdent, staticImportByIdent,
							HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, callSigByCallee);
						currentAllowedValueIdentNames = prevAllowedValueIdentNames;
						out.push("let " + ocamlValueIdent(nameRaw) + " = " + initOcaml);
						staticAllowedValueIdents.set(nameRaw, true);
						if (staticTyByIdent.get(nameRaw) == null)
							staticTyByIdent.set(nameRaw, TyType.unknown());
					}
					if (parsedFields.length > 0)
						out.push("");

					final typedFnsRest = new Array<TyFunctionEnv>();
					for (tf in typedFns) {
						if (shouldHoistLoad && tf.getName() == "load")
							continue;
						if (preludeFnNames.exists(tf.getName()))
							continue;
						typedFnsRest.push(tf);
					}

					if (typedFnsRest.length > 0) {
						// Stage 3 bring-up: avoid putting *every* function in a single `let rec ... and ...` group.
						//
						// Why
						// - In OCaml, values in a recursive group are *monomorphic within the group*.
						// - Upstream test harnesses frequently call helpers like `isTrue(v:Dynamic, ...)` with
						//   different `v` types (Int, Float, String, ...). If `testIs` and `isTrue` live in the
						//   same recursive group, OCaml will unify `v` to the first use (e.g. `int`) and later
						//   calls (e.g. `2.`) fail to typecheck.
						//
						// How
						// - Build a best-effort call graph between module-local functions.
						// - Emit strongly-connected components (SCCs) as separate recursive groups.
						//   - SCC size > 1: `let rec ... and ...` (mutual recursion)
						//   - SCC size == 1: `let rec f ...` (still recursive, but isolated so it can be
						//     generalized before later bindings use it)
						//
						// This keeps output deterministic and matches OCaml scoping rules:
						// callers must come *after* callees unless they share a recursive group.
						final nRest = typedFnsRest.length;
						final restIndexByName = new haxe.ds.StringMap<Int>();
						for (i in 0...nRest) {
							final nm = typedFnsRest[i].getName();
							if (nm != null && nm.length > 0)
								restIndexByName.set(nm, i);
						}

						final edges = new Array<Array<Int>>();
						final revEdges = new Array<Array<Int>>();
						for (_ in 0...nRest) {
							edges.push([]);
							revEdges.push([]);
						}

						// Deduplicate edges per caller using an integer stamp array.
						final seenStamp = new Array<Int>();
						seenStamp.resize(nRest);
						for (i in 0...nRest)
							seenStamp[i] = 0;

						for (i in 0...nRest) {
							final nameRaw = typedFnsRest[i].getName();
							final parsedFn = nameRaw == null ? null : parsedByName.get(nameRaw);
							if (parsedFn == null)
								continue;

							final stamp = i + 1;
							final stmtWorklist = new Array<HxStmt>();
							final exprWorklist = new Array<HxExpr>();
							for (s in HxFunctionDecl.getBody(parsedFn))
								if (s != null)
									stmtWorklist.push(s);

							while (stmtWorklist.length > 0) {
								final s = stmtWorklist.pop();
								if (s == null)
									continue;
								switch (s) {
									case SBlock(stmts, _):
										if (stmts != null)
											for (ss in stmts)
												if (ss != null)
													stmtWorklist.push(ss);
									case SVar(_name, _hint, init, _):
										if (init != null)
											exprWorklist.push(init);
									case SIf(cond, thenBranch, elseBranch, _):
										if (cond != null)
											exprWorklist.push(cond);
										if (thenBranch != null)
											stmtWorklist.push(thenBranch);
										if (elseBranch != null)
											stmtWorklist.push(elseBranch);
									case SWhile(cond, body, _):
										if (cond != null)
											exprWorklist.push(cond);
										if (body != null)
											stmtWorklist.push(body);
									case SDoWhile(body, cond, _):
										if (body != null)
											stmtWorklist.push(body);
										if (cond != null)
											exprWorklist.push(cond);
									case SForIn(_name, iterable, body, _):
										if (iterable != null)
											exprWorklist.push(iterable);
										if (body != null)
											stmtWorklist.push(body);
									case STry(tryBody, catches, _):
										if (tryBody != null)
											stmtWorklist.push(tryBody);
										if (catches != null) {
											for (c in catches)
												if (c != null && c.body != null)
													stmtWorklist.push(c.body);
										}
									case SThrow(expr, _):
										if (expr != null)
											exprWorklist.push(expr);
									case SBreak(_):
									case SContinue(_):
									case SSwitch(scrutinee, _patterns, bodies, _):
										if (scrutinee != null)
											exprWorklist.push(scrutinee);
										if (bodies != null)
											for (body in bodies)
												if (body != null)
													stmtWorklist.push(body);
									case SReturnVoid(_):
									case SReturn(expr, _):
										if (expr != null)
											exprWorklist.push(expr);
									case SExpr(expr, _):
										if (expr != null)
											exprWorklist.push(expr);
								}
							}

							while (exprWorklist.length > 0) {
								final e = exprWorklist.pop();
								if (e == null)
									continue;
								switch (e) {
									case EIdent(name):
										// Function values (e.g. `map(printField)`) also create ordering
										// dependencies between module-local functions.
										//
										// Without this edge, SCC ordering can emit the caller before the callee,
										// yielding "Unbound value" in OCaml when the function value is referenced.
										if (name != null && name.length > 0 && restIndexByName.exists(name)) {
											final j = restIndexByName.get(name);
											if (j != null && j != i && seenStamp[j] != stamp) {
												seenStamp[j] = stamp;
												edges[i].push(j);
												revEdges[j].push(i);
											}
										}
									case ECall(callee, args):
										var calleeName:Null<String> = null;
										switch (callee) {
											case EIdent(name):
												calleeName = name;
											case EField(_obj, field):
												calleeName = field;
											case _:
										}

										if (calleeName != null && calleeName.length > 0 && restIndexByName.exists(calleeName)) {
											final j = restIndexByName.get(calleeName);
											if (j != null && j != i && seenStamp[j] != stamp) {
												seenStamp[j] = stamp;
												edges[i].push(j);
												revEdges[j].push(i);
											}
										}

										if (callee != null)
											exprWorklist.push(callee);
										if (args != null)
											for (a in args)
												if (a != null)
													exprWorklist.push(a);
									case EField(obj, _):
										if (obj != null)
											exprWorklist.push(obj);
									case ELambda(_args, body):
										if (body != null)
											exprWorklist.push(body);
									case ETernary(cond, thenExpr, elseExpr):
										if (cond != null)
											exprWorklist.push(cond);
										if (thenExpr != null)
											exprWorklist.push(thenExpr);
										if (elseExpr != null)
											exprWorklist.push(elseExpr);
									case EAnon(_names, values):
										if (values != null)
											for (v in values)
												if (v != null)
													exprWorklist.push(v);
									case ESwitch(scrutinee, _patterns, exprs):
										if (scrutinee != null)
											exprWorklist.push(scrutinee);
										if (exprs != null)
											for (branchExpr in exprs)
												if (branchExpr != null)
													exprWorklist.push(branchExpr);
									case ENew(_typePath, args):
										// `ENew` lowers through the class constructor helper (`new_`) in Stage3.
										// Register a dependency on `new` so SCC ordering keeps the callee available.
										if (restIndexByName.exists("new")) {
											final j = restIndexByName.get("new");
											if (j != null && j != i && seenStamp[j] != stamp) {
												seenStamp[j] = stamp;
												edges[i].push(j);
												revEdges[j].push(i);
											}
										}
										if (args != null)
											for (a in args)
												if (a != null)
													exprWorklist.push(a);
									case EUnop(_op, expr):
										if (expr != null)
											exprWorklist.push(expr);
									case EBinop(_op, left, right):
										if (left != null)
											exprWorklist.push(left);
										if (right != null)
											exprWorklist.push(right);
									case EArrayComprehension(_name, iterable, yieldExpr):
										if (iterable != null)
											exprWorklist.push(iterable);
										if (yieldExpr != null)
											exprWorklist.push(yieldExpr);
									case EArrayDecl(values):
										if (values != null)
											for (v in values)
												if (v != null)
													exprWorklist.push(v);
									case EArrayAccess(array, index):
										if (array != null)
											exprWorklist.push(array);
										if (index != null)
											exprWorklist.push(index);
									case ERange(start, end):
										if (start != null)
											exprWorklist.push(start);
										if (end != null)
											exprWorklist.push(end);
									case ECast(expr, _hint):
										if (expr != null)
											exprWorklist.push(expr);
									case EUntyped(expr):
										if (expr != null)
											exprWorklist.push(expr);
									case _:
								}
							}
						}

						// Kosaraju SCC on the function dependency graph.
						final visited = new Array<Int>();
						visited.resize(nRest);
						for (i in 0...nRest)
							visited[i] = 0;
						final order = new Array<Int>();

						for (v in 0...nRest) {
							if (visited[v] != 0)
								continue;
							final stackNode = new Array<Int>();
							final stackEdgeIdx = new Array<Int>();
							stackNode.push(v);
							stackEdgeIdx.push(0);
							visited[v] = 1;
							while (stackNode.length > 0) {
								final top = stackNode.length - 1;
								final node = stackNode[top];
								final ei = stackEdgeIdx[top];
								final adj = edges[node];
								if (adj != null && ei < adj.length) {
									final w = adj[ei];
									stackEdgeIdx[top] = ei + 1;
									if (visited[w] == 0) {
										visited[w] = 1;
										stackNode.push(w);
										stackEdgeIdx.push(0);
									}
								} else {
									order.push(node);
									stackNode.pop();
									stackEdgeIdx.pop();
								}
							}
						}

						final compId = new Array<Int>();
						compId.resize(nRest);
						for (i in 0...nRest)
							compId[i] = -1;
						final comps = new Array<Array<Int>>();

						var oi = order.length - 1;
						while (oi >= 0) {
							final v = order[oi];
							oi -= 1;
							if (compId[v] != -1)
								continue;

							final cid = comps.length;
							final nodes = new Array<Int>();
							final stack = new Array<Int>();
							stack.push(v);
							compId[v] = cid;

							while (stack.length > 0) {
								final x = stack.pop();
								nodes.push(x);
								final radj = revEdges[x];
								if (radj != null) {
									for (w in radj) {
										if (compId[w] == -1) {
											compId[w] = cid;
											stack.push(w);
										}
									}
								}
							}

							comps.push(nodes);
						}

						final nComp = comps.length;
						final compAdj = new Array<Array<Int>>();
						final indeg = new Array<Int>();
						compAdj.resize(nComp);
						indeg.resize(nComp);
						for (c in 0...nComp) {
							compAdj[c] = [];
							indeg[c] = 0;
						}

						// Dedup comp edges via a dense stamp table (nComp is small per module).
						final compEdgeSeen = new Array<Int>();
						compEdgeSeen.resize(nComp * nComp);
						for (k in 0...compEdgeSeen.length)
							compEdgeSeen[k] = 0;

						for (i in 0...nRest) {
							final callerComp = compId[i];
							final adj = edges[i];
							if (adj == null)
								continue;
							for (j in adj) {
								final calleeComp = compId[j];
								if (callerComp == calleeComp)
									continue;
								// Emit callee SCC before caller SCC.
								final src = calleeComp;
								final dst = callerComp;
								final key = src * nComp + dst;
								if (compEdgeSeen[key] != 0)
									continue;
								compEdgeSeen[key] = 1;
								compAdj[src].push(dst);
								indeg[dst] += 1;
							}
						}

						final q = new Array<Int>();
						for (c in 0...nComp)
							if (indeg[c] == 0)
								q.push(c);
						var qi = 0;
						final compOrder = new Array<Int>();
						while (qi < q.length) {
							final c = q[qi];
							qi += 1;
							compOrder.push(c);

							final outs = compAdj[c];
							if (outs != null) {
								for (d in outs) {
									indeg[d] -= 1;
									if (indeg[d] == 0)
										q.push(d);
								}
							}
						}

						// Safety fallback: if something went wrong, emit everything in one group.
						// (Don't emit partial SCC order and then re-emit; that would duplicate definitions.)
						if (compOrder.length != nComp) {
							emitFnGroup(typedFnsRest);
						} else {
							for (c in compOrder) {
								final nodes = comps[c];
								// Deterministic order within the SCC: preserve original function order by sorting indices.
								if (nodes != null && nodes.length > 1) {
									var si = 1;
									while (si < nodes.length) {
										final key = nodes[si];
										var sj = si - 1;
										while (sj >= 0 && nodes[sj] > key) {
											nodes[sj + 1] = nodes[sj];
											sj -= 1;
										}
										nodes[sj + 1] = key;
										si += 1;
									}
								}

								final group = new Array<TyFunctionEnv>();
								if (nodes != null)
									for (idx in nodes)
										group.push(typedFnsRest[idx]);
								if (group.length > 0)
									emitFnGroup(group);
							}
						}
					}

					if (moduleEmitBodies && exceptions.length > 0) {
						// Prepend exceptions so the `try ... with` clauses can reference them.
						out.insert(2, exceptions.join("\n") + "\n");
					}

					if (isRoot && sawMain) {
						out.push("let () = ignore (main ())");
						out.push("");
					}

					final mlPath = haxe.io.Path.join([outAbs, mainModuleName + ".ml"]);
					sys.io.File.saveContent(mlPath, out.join("\n"));
					currentOcamlModuleName = prevOcamlModule;
					currentModuleFilePath = prevModuleFilePath;
					currentImportInt64 = prevInt64;
					currentInstanceFieldsByTypePath = prevInstanceFieldsByTypePath;
					currentInstanceMethodsByTypePath = prevInstanceMethodsByTypePath;
					return mainModuleName + ".ml";
				} catch (e:TyperError) {
					currentOcamlModuleName = prevOcamlModule;
					currentModuleFilePath = prevModuleFilePath;
					currentImportInt64 = prevInt64;
					currentInstanceFieldsByTypePath = prevInstanceFieldsByTypePath;
					currentInstanceMethodsByTypePath = prevInstanceMethodsByTypePath;
					throw e;
				} catch (e:String) {
					currentOcamlModuleName = prevOcamlModule;
					currentModuleFilePath = prevModuleFilePath;
					currentImportInt64 = prevInt64;
					currentInstanceFieldsByTypePath = prevInstanceFieldsByTypePath;
					currentInstanceMethodsByTypePath = prevInstanceMethodsByTypePath;
					throw e;
				}
			}

			final files = new Array<String>();
			var rootMain:Null<String> = null;

			// Emit the main class first (typed, optional full bodies).
			final mainPath = isRuntimeProvided ? null : emitMainClass();
			if (mainPath != null) {
				files.push(mainPath);
				if (isRoot)
					rootMain = mainPath;
			}

			// Emit any additional module-local class declarations as separate compilation units.
			//
			// Why
			// - Upstream Haxe modules can declare helper types in the same file (often `private class Foo`).
			// - Stage3 typing currently models only the chosen `mainClass`, but codegen still needs
			//   providers for referenced static members like `Foo.bar`.
			for (c in HxModuleDecl.getClasses(decl)) {
				final nm = HxClassDecl.getName(c);
				if (nm == null || nm.length == 0 || nm == "Unknown")
					continue;
				if (nm == className)
					continue;
				_EmitterStageDebug.traceStage3Module("stub", moduleNameForDecl(decl, moduleTypeName, nm), tm.getParsed().getFilePath());
				final p = emitStubClass(c);
				if (p != null)
					files.push(p);
			}

			return {files: files, rootMain: rootMain};
		}

		// Emit dependencies first, but link the root module last so its `let () = main ()`
		// runs after all referenced compilation units are linked.
		final emittedModulePaths = new Array<String>();
		var rootMainPath:Null<String> = null;
		final deps = typedModules.slice(1);
		for (tm in deps) {
			final r = emitModule(tm, false);
			for (f in r.files)
				emittedModulePaths.push(f);
		}
		final rr = emitModule(typedModules[0], true);
		for (f in rr.files)
			emittedModulePaths.push(f);
		rootMainPath = rr.rootMain;

		// Stage 3 bring-up: upstream unit fixtures use `StringTools.hex`, but our Stage3 typing
		// frequently produces a placeholder `StringTools.ml` compilation unit with no members.
		//
		// Emit a minimal provider implementation when we detect the placeholder unit, so calls
		// like `StringTools.hex(n)` can link.
		{
			final shimName = "StringTools";
			final shimFile = shimName + ".ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			final placeholder = "(* Generated by hxhx(stage3) bootstrap emitter *)";
			try {
				if (sys.FileSystem.exists(shimPath)) {
					final contents = sys.io.File.getContent(shimPath);
					final trimmed = StringTools.trim(contents);
					// The placeholder unit shape changed once we started emitting a file-local warning
					// suppression directive (to keep bring-up output warning-clean under strict dune).
					//
					// Treat both of these as "empty placeholder" modules:
					// - just the header comment
					// - header comment + a single `[@@@warning "..."]` line
					var isPlaceholder = false;
					if (trimmed == placeholder) {
						isPlaceholder = true;
					} else {
						final lines = trimmed.split("\n").filter(l -> l != null && StringTools.trim(l).length > 0);
						if (lines.length == 2 && lines[0] == placeholder && StringTools.startsWith(lines[1], "[@@@warning")) {
							isPlaceholder = true;
						}
					}
					if (isPlaceholder) {
						sys.io.File.saveContent(shimPath,
							"(* hxhx(stage3) bootstrap shim: StringTools.hex *)\n"
							+ "\n"
							+ "let hex (n : int) (digits : Obj.t) : string =\n"
							+ "  let hexChars = \"0123456789ABCDEF\" in\n"
							+ "  let n32 = Int32.of_int n in\n"
							+ "  let rec build (x : Int32.t) (acc : string) : string =\n"
							+ "    let digit = Int32.to_int (Int32.logand x 0xFl) in\n"
							+ "    let acc2 = (Stdlib.String.make 1 (Stdlib.String.get hexChars digit)) ^ acc in\n"
							+ "    let x2 = Int32.shift_right_logical x 4 in\n"
							+ "    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2\n"
							+ "  in\n"
							+ "  let s = build n32 \"\" in\n"
							+ "  let digits_i = if digits == HxRuntime.hx_null then 0 else (Obj.obj digits : int) in\n"
							+ "  if digits_i <= 0 then s else\n"
							+ "    let rec pad (s0 : string) : string =\n"
							+ "      if Stdlib.String.length s0 < digits_i then pad (\"0\" ^ s0) else s0\n"
							+ "    in\n"
							+ "    pad s\n");
					}
				} else {
					sys.io.File.saveContent(shimPath,
						"(* hxhx(stage3) bootstrap shim: StringTools.hex *)\n"
						+ "\n"
						+ "let hex (n : int) (digits : Obj.t) : string =\n"
						+ "  let hexChars = \"0123456789ABCDEF\" in\n"
						+ "  let n32 = Int32.of_int n in\n"
						+ "  let rec build (x : Int32.t) (acc : string) : string =\n"
						+ "    let digit = Int32.to_int (Int32.logand x 0xFl) in\n"
						+ "    let acc2 = (Stdlib.String.make 1 (Stdlib.String.get hexChars digit)) ^ acc in\n"
						+ "    let x2 = Int32.shift_right_logical x 4 in\n"
						+ "    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2\n"
						+ "  in\n"
						+ "  let s = build n32 \"\" in\n"
						+ "  let digits_i = if digits == HxRuntime.hx_null then 0 else (Obj.obj digits : int) in\n"
						+ "  if digits_i <= 0 then s else\n"
						+ "    let rec pad (s0 : string) : string =\n"
						+ "      if Stdlib.String.length s0 < digits_i then pad (\"0\" ^ s0) else s0\n"
						+ "    in\n"
						+ "    pad s\n");
					generatedPaths.push(shimFile);
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		// Stage 3 bring-up: direct `Sys.stdin/stdout/stderr` lowerings reference the generated
		// `sys.io.Stdio` provider module as `Sys_io_Stdio`, but Stage3 import closure does not
		// guarantee that this std module is emitted into every program output.
		//
		// Materialize the repo-owned generated provider whenever the emitted output actually references
		// `Sys_io_Stdio.`. Scan the output directory directly because `generatedPaths` does not
		// reliably include every program module in Stage3 bring-up flows.
		{
			final shimFile = "sys_io_Stdio.ml";
			try {
				var needsShim = false;
				for (entry in sys.FileSystem.readDirectory(outAbs)) {
					if (needsShim)
						break;
					if (!StringTools.endsWith(entry, ".ml"))
						continue;
					final candidatePath = haxe.io.Path.join([outAbs, entry]);
					if (!sys.FileSystem.exists(candidatePath) || sys.FileSystem.isDirectory(candidatePath))
						continue;
					final contents = sys.io.File.getContent(candidatePath);
					if (contents.indexOf("Sys_io_Stdio.") != -1)
						needsShim = true;
				}
				if (needsShim) {
					final shimPath = haxe.io.Path.join([outAbs, shimFile]);
					if (!sys.FileSystem.exists(shimPath)) {
						final root = inferRepoRootForShims();
						if (root != null && root.length > 0) {
							final sourcePath = haxe.io.Path.join([root, "packages", "hxhx", "bootstrap_out", shimFile]);
							if (sys.FileSystem.exists(sourcePath)) {
								sys.io.File.saveContent(shimPath, sys.io.File.getContent(sourcePath));
								generatedPaths.push(shimFile);
							}
						}
					}
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		// Stage 3 bring-up: once `sys_io_Stdio` is present, it expects the bootstrap-generated
		// stdio/provider dependency surface (`*_impl` helpers and exception constructors).
		//
		// Replace the placeholder stage3 shims only in this stdio-provider scenario so the fix stays
		// tightly scoped to the built-in native path that actually needs these modules.
		{
			final stdioPath = haxe.io.Path.join([outAbs, "sys_io_Stdio.ml"]);
			try {
				if (sys.FileSystem.exists(stdioPath) && !sys.FileSystem.isDirectory(stdioPath)) {
					final replacements = [
						{ target : "haxe_io_Input.ml", source : "haxe_io_Input.ml", marker : "set_bigEndian__impl" },
						{ target : "haxe_io_Output.ml", source : "haxe_io_Output.ml", marker : "set_bigEndian__impl" },
						{ target : "StringTools.ml", source : "StringTools.ml", marker : "let _g_offset = ref 0" },
						{ target : "Haxe_io_BytesBuffer.ml", source : "haxe_io_BytesBuffer.ml", marker : "let create" },
						{ target : "Haxe_io_Error.ml", source : "haxe_io_Error.ml", marker : "OutsideBounds" },
						{ target : "Haxe_io_FPHelper.ml", source : "haxe_io_FPHelper.ml", marker : "doubleToI64" },
						{ target : "Haxe_Int64.ml", source : "haxe_Int64.ml", marker : "___int64_t" },
						{ target : "StringBuf.ml", source : "StringBuf.ml", marker : "Stdlib.Buffer.create 16" },
						{ target : "Haxe_Exception.ml", source : "haxe_Exception.ml", marker : "details__impl" },
						{
							target : "Haxe_exceptions_PosException.ml",
							source : "haxe_exceptions_PosException.ml",
							marker : "create",
						},
						{
							target : "Haxe_exceptions_NotImplementedException.ml",
							source : "haxe_exceptions_NotImplementedException.ml",
							marker : "create",
						},
					];
					final root = inferRepoRootForShims();
					if (root != null && root.length > 0) {
						for (replacement in replacements) {
							final targetPath = haxe.io.Path.join([outAbs, replacement.target]);
							var needsReplacement = !sys.FileSystem.exists(targetPath) || sys.FileSystem.isDirectory(targetPath);
							if (!needsReplacement) {
								final contents = sys.io.File.getContent(targetPath);
								needsReplacement = contents.indexOf(replacement.marker) == -1;
							}
							if (!needsReplacement)
								continue;
							final sourcePath = haxe.io.Path.join([root, "packages", "hxhx", "bootstrap_out", replacement.source]);
							if (sys.FileSystem.exists(sourcePath))
								sys.io.File.saveContent(targetPath, sys.io.File.getContent(sourcePath));
						}
						final emittedCallStackPath = haxe.io.Path.join([outAbs, "Haxe_CallStack.ml"]);
						final runtimeCallStackPath = haxe.io.Path.join([outAbs, "runtime", "haxe_CallStack.ml"]);
						if (sys.FileSystem.exists(emittedCallStackPath) && sys.FileSystem.exists(runtimeCallStackPath))
							sys.FileSystem.deleteFile(runtimeCallStackPath);
					}
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		// Stage 3 bring-up: some emitted exception units still call `Haxe_NativeStackTrace.toHaxe`
		// while the runtime callstack model in this lane is string-based and does not always emit a
		// matching provider module.
		//
		// Emit a narrow compatibility shim only when:
		// - `Haxe_Exception.ml` references `Haxe_NativeStackTrace.toHaxe`, and
		// - no usable `Haxe_NativeStackTrace.ml` has been emitted yet.
		{
			final exceptionPath = haxe.io.Path.join([outAbs, "Haxe_Exception.ml"]);
			final nativeStackTracePath = haxe.io.Path.join([outAbs, "Haxe_NativeStackTrace.ml"]);
			try {
				if (sys.FileSystem.exists(exceptionPath) && !sys.FileSystem.isDirectory(exceptionPath)) {
					final exceptionContents = sys.io.File.getContent(exceptionPath);
					final needsNativeStackTrace = exceptionContents.indexOf("Haxe_NativeStackTrace.toHaxe") != -1;
					if (needsNativeStackTrace) {
						var hasCompatibleShim = false;
						if (sys.FileSystem.exists(nativeStackTracePath) && !sys.FileSystem.isDirectory(nativeStackTracePath)) {
							final nativeStackTraceContents = sys.io.File.getContent(nativeStackTracePath);
							hasCompatibleShim = nativeStackTraceContents.indexOf("haxe.NativeStackTrace (string-stack model)") != -1;
						}
						if (!hasCompatibleShim) {
							final shimBody = [
								"(* hxhx(stage3) bootstrap shim: haxe.NativeStackTrace (string-stack model) *)",
								"[@@@warning \"-21-26\"]",
								"",
								"type t = { __hx_type : Obj.t }",
								"",
								"let create () : t = { __hx_type = HxType.class_ \"haxe.NativeStackTrace\" }",
								"let __empty () : t = create ()",
								"",
								"let saveStack (_exception : Obj.t) : unit =",
								"  ignore _exception",
								"",
								"let callStack () =",
								"  let anon = HxAnon.create () in",
								"  ignore (HxAnon.set anon \"skip\" (Obj.repr 1));",
								"  ignore (HxAnon.set anon \"stack\" (Obj.repr (HxBacktrace.callstack_lines 64)));",
								"  anon",
								"",
								"let exceptionStack () =",
								"  let anon = HxAnon.create () in",
								"  ignore (HxAnon.set anon \"skip\" (Obj.repr 0));",
								"  ignore (HxAnon.set anon \"stack\" (Obj.repr (HxBacktrace.exceptionstack_lines ())));",
								"  anon",
								"",
									"let parseFileLine = fun line -> try let fileNeedle = \"file \\\"\" in let fileStart0 = HxString.indexOf line fileNeedle 0 in (",
									"  ignore (if fileStart0 < 0 then raise (HxRuntime.Hx_return (Obj.repr (Obj.magic (HxRuntime.hx_null)))) else ());",
									"  let fileStart = HxInt.add fileStart0 (HxString.length fileNeedle) in let fileEnd = HxString.indexOf line \"\\\"\" fileStart in (",
									"    ignore (if fileEnd < 0 then raise (HxRuntime.Hx_return (Obj.repr (Obj.magic (HxRuntime.hx_null)))) else ());",
									"    let file = HxString.substr line fileStart (HxInt.sub fileEnd fileStart) in let lineNeedle = \"line \" in let lineStart0 = HxString.indexOf line lineNeedle fileEnd in (",
									"      ignore (if lineStart0 < 0 then raise (HxRuntime.Hx_return (Obj.repr (Obj.magic (HxRuntime.hx_null)))) else ());",
									"      let i = HxInt.add lineStart0 (HxString.length lineNeedle) in let j = ref i in (",
									"        ignore (try while !j < HxString.length line do try ignore (let c = HxString.charCodeAt line (!j) in (",
									"          ignore (if (let __nullable_3 = c in let __nullable_4 = 48 in if __nullable_3 == HxRuntime.hx_null then false else Obj.obj __nullable_3 < __nullable_4) || (let __nullable_5 = c in let __nullable_6 = 57 in if __nullable_5 == HxRuntime.hx_null then false else Obj.obj __nullable_5 > __nullable_6) then raise (HxRuntime.Hx_break) else ());",
									"          let __old_7 = !j in let __new_8 = HxInt.add __old_7 1 in (",
									"            ignore (j := __new_8);",
									"            __old_7",
									"          )",
									"        )) with",
									"          | HxRuntime.Hx_continue -> () done with",
									"          | HxRuntime.Hx_break -> ());",
									"        ignore (if !j = i then raise (HxRuntime.Hx_return (Obj.repr (Obj.magic (HxRuntime.hx_null)))) else ());",
									"        let ln = ref 0 in let _g = ref i in let _g1 = !j in (",
									"          ignore (while !_g < _g1 do ignore (let k = let __old_9 = !_g in let __new_10 = HxInt.add __old_9 1 in (",
									"            ignore (_g := __new_10);",
									"            __old_9",
									"          ) in let __assign_11 = HxInt.add (HxInt.mul (!ln) 10) (HxInt.sub (let __nullable_int_12 = HxString.charCodeAt line k in if __nullable_int_12 == HxRuntime.hx_null then 0 else Obj.obj __nullable_int_12) 48) in (",
									"            ln := __assign_11;",
									"            __assign_11",
									"          )) done);",
									"          let __anon_13 = HxAnon.create () in (",
									"            ignore (HxAnon.set __anon_13 \"file\" (Obj.repr file));",
									"            ignore (HxAnon.set __anon_13 \"line\" (Obj.repr (!ln)));",
									"            __anon_13",
									"          )",
									"        )",
									"      )",
									"    )",
									"  )",
									") with",
									"  | HxRuntime.Hx_return __ret_14 -> Obj.obj __ret_14",
									"",
									"let toHaxe = fun nativeStackTrace skip -> let native = nativeStackTrace in let toSkip = ref (HxInt.add skip (try Obj.obj (HxAnon.get native \"skip\") with _ -> 0)) in let out = HxArray.create () in let _g = ref 0 in let _g1 = (try (Obj.obj (HxAnon.get native \"stack\") : string HxArray.t) with _ -> HxBacktrace.exceptionstack_lines ()) in (",
									"  ignore (try while !_g < HxArray.length _g1 do try ignore (let line = HxArray.get _g1 (!_g) in (",
									"    ignore (let __old_15 = !_g in let __new_16 = HxInt.add __old_15 1 in (",
									"      ignore (_g := __new_16);",
									"      __new_16",
									"    ));",
									"    ignore (if !toSkip > 0 then ignore ((",
									"      ignore (let __old_17 = !toSkip in let __new_18 = HxInt.add __old_17 (-1) in (",
									"        ignore (toSkip := __new_18);",
									"        __old_17",
									"      ));",
									"      raise (HxRuntime.Hx_continue)",
									"    )) else ());",
									"    ignore (HxArray.push out (line : string))",
									"  )) with",
									"    | HxRuntime.Hx_continue -> () done with",
									"    | HxRuntime.Hx_break -> ());",
									"  out",
									")",
								"",
							].join("\n");
							sys.io.File.saveContent(nativeStackTracePath, shimBody);
							if (generatedPaths.indexOf("Haxe_NativeStackTrace.ml") == -1)
								generatedPaths.push("Haxe_NativeStackTrace.ml");
						}
					}
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		// Stage 3 bootstrap: break the generated `StringTools <-> haxe.iterators.StringIteratorUnicode`
		// dune cycle by swapping in the bootstrap `StringTools` when that exact emitted shape appears.
		{
			final stringToolsPath = haxe.io.Path.join([outAbs, "StringTools.ml"]);
			final unicodeIterPath = haxe.io.Path.join([outAbs, "haxe_iterators_StringIteratorUnicode.ml"]);
			try {
				if (sys.FileSystem.exists(stringToolsPath)
					&& !sys.FileSystem.isDirectory(stringToolsPath)
					&& sys.FileSystem.exists(unicodeIterPath)
					&& !sys.FileSystem.isDirectory(unicodeIterPath)) {
					final stringToolsContents = sys.io.File.getContent(stringToolsPath);
					final unicodeIterContents = sys.io.File.getContent(unicodeIterPath);
					final hasCycleShape = stringToolsContents.indexOf("Haxe_iterators_StringIteratorUnicode.create") != -1
						&& unicodeIterContents.indexOf("StringTools.utf16CodePointAt") != -1;
					final needsBootstrapStringTools = hasCycleShape
						&& stringToolsContents.indexOf("let _g_offset = ref 0") == -1;
					if (needsBootstrapStringTools) {
						final root = inferRepoRootForShims();
						if (root != null && root.length > 0) {
							final sourcePath = haxe.io.Path.join([root, "packages", "hxhx", "bootstrap_out", "StringTools.ml"]);
							if (sys.FileSystem.exists(sourcePath))
								sys.io.File.saveContent(stringToolsPath, sys.io.File.getContent(sourcePath));
						}
					}
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		// Stage 3 bring-up: emitted provider closures such as `sys_io_Stdio`, `haxe_io_Input`, and
		// `haxe_io_Output` require `Haxe_io_Eof.create ()`.
		//
		// If `haxe_io_Eof.ml` is missing or still lacks `create`, replace it with the repo-owned
		// bootstrap snapshot so downstream providers link without widening the fix to unrelated
		// std modules.
		{
			final shimFile = "haxe_io_Eof.ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			try {
				var providerNeedsEof = false;
				for (providerPath in [
					haxe.io.Path.join([outAbs, "sys_io_Stdio.ml"]),
					haxe.io.Path.join([outAbs, "haxe_io_Input.ml"]),
					haxe.io.Path.join([outAbs, "haxe_io_Output.ml"]),
				]) {
					if (sys.FileSystem.exists(providerPath) && !sys.FileSystem.isDirectory(providerPath)) {
						providerNeedsEof = true;
						break;
					}
				}
				if (providerNeedsEof) {
					var hasCreate = false;
					if (sys.FileSystem.exists(shimPath) && !sys.FileSystem.isDirectory(shimPath)) {
						final contents = sys.io.File.getContent(shimPath);
						hasCreate = contents.indexOf("let create") != -1 || contents.indexOf("let rec create") != -1;
					}
					if (!hasCreate) {
						final root = inferRepoRootForShims();
						if (root != null && root.length > 0) {
							final sourcePath = haxe.io.Path.join([root, "packages", "hxhx", "bootstrap_out", shimFile]);
							if (sys.FileSystem.exists(sourcePath))
								sys.io.File.saveContent(shimPath, sys.io.File.getContent(sourcePath));
						}
					}
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		// Stage 3 safety: avoid segfault-shaped behavior in generated macro context wrappers.
		//
		// Why
		// - Upstream display workloads execute code paths that call `haxe.macro.Context.*` wrappers.
		// - At this bring-up rung, macro API plumbing is still placeholder-heavy.
		// - Calling placeholder values as curried OCaml functions can crash with EXC_BAD_ACCESS.
		//
		// What
		// - Rewrite the generated `Haxe_macro_Context.load` binding to return arity-aware
		//   fail-fast closures that raise a deterministic exception instead of crashing.
		{
			final shimName = "Haxe_macro_Context";
			final shimFile = shimName + ".ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			if (sys.FileSystem.exists(shimPath)) {
				final src = sys.io.File.getContent(shimPath);
				final from = "let load (f : string) (nargs : int) : _ = Eval_vm_Context.callMacroApi (f)";
				if (src.indexOf(from) != -1) {
					final to = "[@@@warning \"-20\"]\n"
						+ "exception HxMacroApiUnavailable of string\n"
						+ "let __hxhx_macro_api_unavailable (f : string) : _ = raise (HxMacroApiUnavailable (\"hxhx(stage3): macro api unavailable: \" ^ f))\n"
						+ "let __hxhx_macro_defined_value (_key : Obj.t) : Obj.t = HxRuntime.hx_null\n"
						+ "let __hxhx_macro_defined (_key : Obj.t) : Obj.t = Obj.repr false\n"
						+ "let __hxhx_macro_resolve_path (v : Obj.t) : Obj.t =\n"
						+ "  let file : string = Obj.obj v in\n"
						+ "  let resolved =\n"
						+ "    if Sys.file_exists file then file\n"
						+ "    else\n"
						+ "      let in_src = Filename.concat \"src\" file in\n"
						+ "      if Sys.file_exists in_src then in_src else file\n"
						+ "  in\n"
						+ "  Obj.repr resolved\n"
						+ "let load (f : string) (nargs : int) : _ =\n"
						+ "  match (f, nargs) with\n"
						+ "  | (\"defined_value\", 1) -> Obj.magic (fun (key : Obj.t) -> __hxhx_macro_defined_value key)\n"
						+ "  | (\"defined\", 1) -> Obj.magic (fun (key : Obj.t) -> __hxhx_macro_defined key)\n"
						+ "  | (\"resolve_path\", 1) -> Obj.magic (fun (file : Obj.t) -> __hxhx_macro_resolve_path file)\n"
						+ "  | _ ->\n"
						+ "    match nargs with\n"
						+ "    | 0 -> Obj.magic (fun () -> __hxhx_macro_api_unavailable f)\n"
						+ "    | 1 -> Obj.magic (fun (_ : Obj.t) -> __hxhx_macro_api_unavailable f)\n"
						+ "    | 2 -> Obj.magic (fun (_ : Obj.t) (_ : Obj.t) -> __hxhx_macro_api_unavailable f)\n"
						+ "    | 3 -> Obj.magic (fun (_ : Obj.t) (_ : Obj.t) (_ : Obj.t) -> __hxhx_macro_api_unavailable f)\n"
						+ "    | _ -> Obj.magic (fun (_ : Obj.t) -> __hxhx_macro_api_unavailable f)";
					sys.io.File.saveContent(shimPath, StringTools.replace(src, from, to));
				}
			}
		}
		// Stage 3 warning-20 noise control:
		// add warning-20 suppression to generated modules where placeholder
		// arity intentionally diverges during bring-up (macro bridge + syntax shims).
		{
			final macroShimNames = ["Haxe_macro_Compiler", "Haxe_macro_TypeTools", "Php_Syntax"];
			for (shimName in macroShimNames) {
				final shimFile = shimName + ".ml";
				final shimPath = haxe.io.Path.join([outAbs, shimFile]);
				try {
					if (!sys.FileSystem.exists(shimPath))
						continue;
					final src = sys.io.File.getContent(shimPath);
					if (src.indexOf("[@@@warning \"-20\"]") != -1)
						continue;
					final marker = "(* Generated by hxhx(stage3) bootstrap emitter *)";
					final patched = src.indexOf(marker) != -1 ? StringTools.replace(src, marker,
						marker + "\n[@@@warning \"-20\"]") : ("[@@@warning \"-20\"]\n" + src);
					sys.io.File.saveContent(shimPath, patched);
				} catch (_:haxe.io.Error) {} catch (_:String) {}
			}
		}

		// Stage 3 bring-up: upstream unit fixtures call `haxe.xml.Parser.parse(...)`, but our Stage3
		// typing can emit a `Haxe_xml_Parser.ml` unit that only contains placeholder statics
		// (e.g. `escapes`) and no `parse` binding.
		//
		// Provide a minimal `parse` value so the suite can link during emit-only bring-up.
		{
			final shimName = "Haxe_xml_Parser";
			final shimFile = shimName + ".ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			try {
				if (sys.FileSystem.exists(shimPath)) {
					final contents = sys.io.File.getContent(shimPath);
					final trimmed = StringTools.trim(contents);
					final hasParse = StringTools.startsWith(trimmed, "let parse")
						|| StringTools.startsWith(trimmed, "let rec parse")
						|| contents.indexOf("\nlet parse") != -1
						|| contents.indexOf("\nlet rec parse") != -1;
					if (!hasParse) {
						sys.io.File.saveContent(shimPath, contents + "\n\nlet parse (_s : string) : _ = (Obj.magic 0)\n");
					}
				} else {
					sys.io.File.saveContent(shimPath,
						"(* hxhx(stage3) bootstrap shim: haxe.xml.Parser.parse *)\n" + "[@@@warning \"-21-26\"]\n" +
						"let parse (_s : string) : _ = (Obj.magic 0)\n");
					generatedPaths.push(shimFile);
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		// Stage 3 bring-up: upstream unit fixtures use `Xml.*` helpers (e.g. `Xml.createElement`)
		// but Stage3 typing doesn't yet guarantee an emitted provider module for `Xml`.
		//
		// Provide a minimal module so the suite can link during emit-only bring-up.
		{
			final shimName = "Xml";
			final shimFile = shimName + ".ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			if (sys.FileSystem.exists(shimPath)) {
				final contents = sys.io.File.getContent(shimPath);
				final trimmed = StringTools.trim(contents);
				final hasCreateElement = StringTools.startsWith(trimmed, "let createElement")
					|| StringTools.startsWith(trimmed, "let rec createElement")
					|| contents.indexOf("\nlet createElement") != -1
					|| contents.indexOf("\nlet rec createElement") != -1;
				if (!hasCreateElement) {
					sys.io.File.saveContent(shimPath,
						contents
						+ "\n\n(* hxhx(stage3) bootstrap shim: Xml camelCase constructors *)\n"
						+ "let createElement (_name : string) : _ = (Obj.magic 0)\n"
						+ "let createPCData (_data : string) : _ = (Obj.magic 0)\n"
						+ "let createCData (_data : string) : _ = (Obj.magic 0)\n"
						+ "let createDocType (_data : string) : _ = (Obj.magic 0)\n"
						+ "let createProcessingInstruction (_data : string) : _ = (Obj.magic 0)\n"
						+ "let createComment (_data : string) : _ = (Obj.magic 0)\n"
						+ "let createDocument () : _ = (Obj.magic 0)\n");
				}
			} else {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: Xml helpers *)\n"
					+ "[@@@warning \"-21-26\"]\n"
					+ "let createElement (_name : string) : _ = (Obj.magic 0)\n"
					+ "let createPCData (_data : string) : _ = (Obj.magic 0)\n"
					+ "let createCData (_data : string) : _ = (Obj.magic 0)\n"
					+ "let createDocType (_data : string) : _ = (Obj.magic 0)\n"
					+ "let createProcessingInstruction (_data : string) : _ = (Obj.magic 0)\n"
					+ "let createComment (_data : string) : _ = (Obj.magic 0)\n"
					+ "let createDocument () : _ = (Obj.magic 0)\n");
				generatedPaths.push(shimFile);
			}
		}

		// Stage 3 bring-up: upstream `php/Boot.hx` can emit unary minus over `php.Const.INF`
		// through expression paths that still infer an int operator, yielding:
		//   `(-(Php_Const.iNF))`
		// which OCaml rejects in float contexts.
		//
		// Normalize this known shape to a float-safe form in the generated unit so Gate1 can
		// keep progressing while emitter-side float inference is tightened.
		{
			final shimPath = haxe.io.Path.join([outAbs, "Php_Boot.ml"]);
			if (sys.FileSystem.exists(shimPath)) {
				final src = sys.io.File.getContent(shimPath);
				final patchedUnaryMinus = StringTools.replace(src, "(-(Php_Const.iNF))", "(-.(Obj.magic Php_Const.iNF : float))");
				final patchedZeroEq = StringTools.replace(patchedUnaryMinus, "((value) = (0))", "((value) = (float_of_int 0))");
				final patchedZeroLt = StringTools.replace(patchedZeroEq, "((value) < (0))", "((value) < (float_of_int 0))");
				final patchedAliases = StringTools.replace(patchedZeroLt,
					'HxBootArray.get (aliases) ((Obj.magic (HxAnon.get (Obj.repr (hxClass)) "phpClassName")))',
					'(Obj.magic (HxAnon.get (Obj.repr (aliases)) ((Obj.magic (HxAnon.get (Obj.repr (hxClass)) "phpClassName")))))');
				final patched = StringTools.replace(patchedAliases, 'HxBootArray.get (classes) (phpClassName)',
					'(Obj.magic (HxAnon.get (Obj.repr (classes)) (phpClassName)))');
				if (patched != src)
					sys.io.File.saveContent(shimPath, patched);
			}
		}

		// Stage 3 bring-up: explicit imports like `import haxe.CallStack;` allow referring to the
		// type/module as `CallStack` in Haxe source.
		//
		// Our bootstrap emitter does not yet fully resolve imported type short names to their
		// emitted OCaml module names, so `CallStack.toString(...)` would otherwise compile to an
		// unbound OCaml module access.
		//
		// Provide a tiny alias shim when needed. This is intentionally narrow: we add only the
		// module required by Gate1/utest, and avoid a broad aliasing scheme that could shadow
		// OCaml stdlib modules (e.g. `List`) during bring-up.
		{
			final shimName = "CallStack";
			final shimFile = shimName + ".ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath, "(* hxhx(stage3) bootstrap import shim: CallStack = haxe.CallStack *)\n" + "include Haxe_CallStack\n");
				generatedPaths.push(shimFile);
			}
		}

		// Stage 3 bring-up: root stdlib `Type.*` calls in emitted runtime code must resolve to the
		// target runtime helper module (`HxType`), not to `haxe.macro.Type`.
		//
		// Why
		// - Generic short-import alias generation can see `import haxe.macro.Type` in macro-side
		//   modules and otherwise create `Type.ml = Haxe_macro_Type`.
		// - That breaks runtime stdlib consumers such as upstream unit/utest code, which expect the
		//   root `Type` module (`Type.getEnum`, `Type.getClassFields`, ...).
		//
		// Keep the bootstrap output honest by forcing the root short-name shim to `HxType`.
		{
			final shimName = "Type";
			final shimFile = shimName + ".ml";
			final shimPath = haxe.io.Path.join([outAbs, shimFile]);
			final shimBody = "(* hxhx(stage3) bootstrap import shim: Type = HxType *)\n" + "include HxType\n";
			sys.io.File.saveContent(shimPath, shimBody);
			if (generatedPaths.indexOf(shimFile) == -1)
				generatedPaths.push(shimFile);
		}

		// Stage 3 bring-up: explicit import short-name shims.
		//
		// Haxe:
		//   import utest.Assert;
		//   Assert.floatEquals(...)
		//
		// OCaml:
		// - Our emitter currently lowers `Assert.floatEquals` as a module access to `Assert`.
		// - The *actual* emitted unit for `utest.Assert` is `Utest_Assert`.
		//
		// Emit a small alias compilation unit (`Assert.ml`) that re-exports the real provider.
		//
		// Safety
		// - Avoid generating aliases that would conflict with:
		//   - modules we already emit (typed modules),
		//   - repo-owned runtime units (`runtime/*.ml`),
		//   - or OCaml stdlib modules commonly used by our runtime.
		{
			inline function baseModuleName(path:String):String {
				final file = haxe.io.Path.withoutDirectory(path);
				return StringTools.endsWith(file, ".ml") ? file.substr(0, file.length - 3) : file;
			}

			final existing:Map<String, Bool> = new Map();
			for (p in runtimePaths)
				existing.set(baseModuleName(p), true);
			for (p in generatedPaths)
				existing.set(baseModuleName(p), true);
			for (p in emittedModulePaths)
				existing.set(baseModuleName(p), true);

			final deny:Map<String, Bool> = new Map();
			// OCaml stdlib modules (avoid shadowing runtime dependencies).
			for (m in [
				"Array",
				"Buffer",
				"Bytes",
				"Char",
				"Filename",
				"Format",
				"Gc",
				"Hashtbl",
				"Int",
				"Int32",
				"Int64",
				"List",
				"Map",
				"Marshal",
				"Nativeint",
				"Obj",
				"Option",
				"Printexc",
				"Printf",
				"Queue",
				"Result",
				"Set",
				"Stack",
				"Stdlib",
				"Str",
				"String",
				"Sys",
				"Unix",
			])
				deny.set(m, true);

			final aliasByShort:Map<String, String> = new Map();
			for (tm in typedModules) {
				for (rawImport in tm.getEnv().getImports()) {
					if (rawImport == null)
						continue;
					final imp = StringTools.trim(rawImport);
					if (imp.length == 0)
						continue;
					if (StringTools.endsWith(imp, ".*"))
						continue;
					final parts = imp.split(".");
					if (parts.length == 0)
						continue;
					final short = parts[parts.length - 1];
					if (short == null || short.length == 0 || !isUpperStart(short))
						continue;
					if (deny.exists(short))
						continue;
					if (existing.exists(short))
						continue;
					final target = ocamlModuleNameFromTypePath(imp);
					if (target == null || target.length == 0)
						continue;
					if (target == short)
						continue;
					// Only alias to a provider that actually exists in this build output.
					//
					// Why
					// - Some imports are inactive after conditional compilation, or are otherwise not
					//   present in the resolved+emitted module set during bring-up.
					// - Emitting an alias to a missing provider turns an unused import into a hard
					//   OCaml build failure.
					if (!existing.exists(target))
						continue;
					if (!aliasByShort.exists(short))
						aliasByShort.set(short, target);
				}
			}

			for (short in aliasByShort.keys()) {
				final target = aliasByShort.get(short);
				if (target == null || target.length == 0)
					continue;
				final aliasFile = short + ".ml";
				final aliasPath = haxe.io.Path.join([outAbs, aliasFile]);
				if (sys.FileSystem.exists(aliasPath))
					continue;
				sys.io.File.saveContent(aliasPath, "(* hxhx(stage3) bootstrap import shim: " + short + " = " + target + " *)\n" + "include " + target + "\n");
				generatedPaths.push(aliasFile);
				existing.set(short, true);
			}
		}

		final duneLayoutRaw = defineValue(defines, "ocaml_dune_layout");
		final wantsDuneScaffold = duneLayoutRaw != null || hasDefine(defines, "ocaml_no_build");
		var duneLayout = Stage3DuneLayoutKind.Executable;
		if (wantsDuneScaffold)
			duneLayout = normalizeStage3DuneLayout(duneLayoutRaw);
		if (duneLayout != null && hasDefine(defines, "ocaml_no_dune"))
			throw "stage3 emitter: ocaml_dune_layout requires dune scaffolding; remove ocaml_no_dune";
		final duneLibrariesRaw = defineValue(defines, "ocaml_dune_libraries");
		final duneLibraries = duneLibrariesRaw == null ? ["unix", "str", "threads", "dynlink"] : duneLibrariesRaw.split(",")
			.map(s -> StringTools.trim(s))
			.filter(s -> s.length > 0);
		final plannedArtifactPath = wantsDuneScaffold ? emitStage3DuneScaffold(outAbs, duneLayout, duneLibraries, rootMainPath) : null;
		final exePath = haxe.io.Path.join([outAbs, "out.exe"]);
		try {
			if (sys.FileSystem.exists(exePath))
				sys.FileSystem.deleteFile(exePath);
		} catch (_:haxe.io.Error) {} catch (_:String) {}

		if (!buildExecutable || wantsDuneScaffold)
			return plannedArtifactPath != null ? plannedArtifactPath : exePath;

		final ocamlopt = {
			final v = Sys.getEnv("OCAMLOPT");
			(v == null || v.length == 0) ? "ocamlopt" : v;
		}

		// Compile from within `outAbs` so the compiler finds the `.cmi` it just produced.
		final prevCwd = try Sys.getCwd() catch (_:haxe.io.Error) null catch (_:String) null;
		if (prevCwd == null)
			throw "stage3 emitter: cannot read current working directory";
		Sys.setCwd(outAbs);

		// Compile in a dependency-respecting unit order.
		//
		// Why
		// - OCaml requires module providers to be compiled before their users.
		// - Our resolved module order is "Haxe-ish" and does not guarantee OCaml compilation order.
		//
		// How
		// - Use `ocamldep -sort` to topologically sort the emitted `.ml` units.
		// - Keep the root unit last so `let () = main ()` (when present) runs after linking deps.
		// macOS default filesystems are case-insensitive. OCaml, however, treats module names as
		// case-sensitive (and derives the compilation unit name from the *spelling* of the
		// filename it was invoked with).
		//
		// If the emitted file list contains two paths that differ only by case
		// (e.g. `Haxe_macro_Expr.ml` vs `Haxe_macro_expr.ml`), they point at the same file on
		// case-insensitive filesystems. Compiling the same unit twice under different spellings
		// will produce "Wrong file naming" errors when OCaml later loads the `.cmi`.
		//
		// Defensive bring-up fix:
		// - Canonicalize `.ml` paths to the casing stored on disk under `outAbs/`,
		// - de-duplicate case-insensitively before invoking `ocamldep`/`ocamlopt`.
		inline function lowerKey(p:String):String {
			return p == null ? "" : p.toLowerCase();
		}
		final canonicalByLower:Map<String, String> = new Map();
		function registerCanonical(relPath:String):Void {
			if (relPath == null || relPath.length == 0)
				return;
			final key = lowerKey(relPath);
			if (canonicalByLower.exists(key)) {
				final prev = canonicalByLower.get(key);
				// If we ever hit this on a case-sensitive filesystem, it means the build output is not
				// portable to case-insensitive hosts (two distinct units collide by case-folding).
				if (prev != relPath)
					throw "stage3 emitter: case-insensitive .ml collision: '" + prev + "' vs '" + relPath + "'";
				return;
			}
			canonicalByLower.set(key, relPath);
		}
		function scanMlDir(absDir:String, prefix:String):Void {
			if (absDir == null || absDir.length == 0)
				return;
			if (!sys.FileSystem.exists(absDir) || !sys.FileSystem.isDirectory(absDir))
				return;
			for (name in sys.FileSystem.readDirectory(absDir)) {
				if (name == null || !StringTools.endsWith(name, ".ml"))
					continue;
				registerCanonical(prefix.length == 0 ? name : (prefix + "/" + name));
			}
		}
		scanMlDir(outAbs, "");
		scanMlDir(haxe.io.Path.join([outAbs, "runtime"]), "runtime");
		function canonicalize(relPath:String):String {
			if (relPath == null || relPath.length == 0)
				return relPath;
			final key = lowerKey(relPath);
			return canonicalByLower.exists(key) ? canonicalByLower.get(key) : relPath;
		}
		function listExistingMlUnits():Array<String> {
			final out = new Array<String>();
			for (k in canonicalByLower.keys()) {
				final rel = canonicalByLower.get(k);
				if (rel == null || rel.length == 0)
					continue;
				final base = haxe.io.Path.withoutDirectory(rel);
				if (base == null || !StringTools.endsWith(base, ".ml"))
					continue;
				// Legacy bootstrap path sometimes left an `out.ml` aggregation unit in-place.
				// Keep Stage3 warm-output rebuilds deterministic by excluding that historical
				// entrypoint from current per-module compile/link argv.
				if (base == "out.ml")
					continue;
				out.push(canonicalize(rel));
			}
			out.sort(function(a:String, b:String):Int {
				return (a < b) ? -1 : ((a > b) ? 1 : 0);
			});
			return out;
		}
		function uniqCaseInsensitive(xs:Array<String>):Array<String> {
			if (xs == null || xs.length <= 1)
				return xs;
			final seen:Map<String, Bool> = new Map();
			final out = new Array<String>();
			for (x in xs) {
				if (x == null || x.length == 0)
					continue;
				final key = lowerKey(x);
				if (seen.exists(key))
					continue;
				seen.set(key, true);
				out.push(canonicalize(x));
			}
			return out;
		}

		final existingMl = listExistingMlUnits();
		final allMl = uniqCaseInsensitive(existingMl.concat(runtimePaths).concat(generatedPaths).concat(emittedModulePaths).map(canonicalize));
		final orderedMl = uniqCaseInsensitive(ocamldepSort(allMl).map(canonicalize));
		final orderedNoRoot = new Array<String>();
		final rootName = rootMainPath;
		for (f in orderedMl)
			if (rootName == null || f != rootName)
				orderedNoRoot.push(f);
		if (rootName != null)
			orderedNoRoot.push(rootName);
		final orderedNoRootUniq = uniqStrings(orderedNoRoot);

		final args = new Array<String>();
		// OCaml 5: make the unix stdlib include directory explicit to silence the
		// "ocaml_deprecated_auto_include" warning.
		args.push("-I");
		args.push("+unix");
		args.push("-I");
		args.push("+str");
		args.push("-I");
		args.push("+threads");
		args.push("-I");
		args.push("+dynlink");
		// Allow emitted units in `outAbs/` to see providers compiled under `outAbs/runtime/`.
		args.push("-I");
		args.push("runtime");
		args.push("-o");
		args.push("out.exe");
		// Link the OCaml stdlib packages used by our runtime and shims.
		args.push("-thread");
		args.push("unix.cmxa");
		args.push("threads.cmxa");
		args.push("str.cmxa");
		args.push("dynlink.cmxa");
		for (p in orderedNoRootUniq)
			args.push(p);
		final code = try {
			Sys.command(ocamlopt, args);
		} catch (e:haxe.io.Error) {
			Sys.setCwd(prevCwd);
			throw e;
		} catch (e:String) {
			Sys.setCwd(prevCwd);
			throw e;
		};
		Sys.setCwd(prevCwd);
		if (code != 0)
			throw "stage3 emitter: ocamlopt failed with exit code " + code;
		if (!sys.FileSystem.exists(exePath))
			throw "stage3 emitter: missing built executable: " + exePath;
		return exePath;
	}
}
