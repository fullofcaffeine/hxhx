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

private class _PortableMetalizationScope {
	public final previousPlan:Null<backend.ocaml.PortableMetalizationPlan>;
	public final previousRegionKey:String;

	public function new(previousPlan:Null<backend.ocaml.PortableMetalizationPlan>, previousRegionKey:String) {
		this.previousPlan = previousPlan;
		this.previousRegionKey = previousRegionKey;
	}
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
			final stderr = Sys.stderr();
			stderr.writeString("stage3_emit_phase=" + label + "\n");
			stderr.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	public static function traceStage3Module(label:String, moduleName:String, filePath:Null<String>):Void {
		if (!traceStage3Enabled())
			return;
		try {
			final fileTag = filePath == null ? "<unknown>" : filePath;
			final stderr = Sys.stderr();
			stderr.writeString("stage3_emit[" + label + "]=" + moduleName + " file=" + fileTag + "\n");
			stderr.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}
	}

	public static function traceStage3StmtList(phase:String, functionName:Null<String>, idx:Int, total:Int, stmt:HxStmt):Void {
		if (!traceStage3Enabled())
			return;
		final fn = functionName == null ? "" : functionName;
		final traceEnv = Sys.getEnv("HXHX_TRACE_STAGE3_STMT_LIST");
		final traceAll = traceEnv == "1" || traceEnv == "true" || traceEnv == "yes";
		if (!traceAll && fn != "emitToDir")
			return;
		final kindAndPos = switch (stmt) {
			case SBlock(_, pos): {kind: "SBlock", pos: pos};
			case SVar(_, _, _, pos): {kind: "SVar", pos: pos};
			case SIf(_, _, _, pos): {kind: "SIf", pos: pos};
			case SWhile(_, _, pos): {kind: "SWhile", pos: pos};
			case SDoWhile(_, _, pos): {kind: "SDoWhile", pos: pos};
			case SForIn(_, _, _, pos): {kind: "SForIn", pos: pos};
			case STry(_, _, pos): {kind: "STry", pos: pos};
			case SThrow(_, pos): {kind: "SThrow", pos: pos};
			case SBreak(pos): {kind: "SBreak", pos: pos};
			case SContinue(pos): {kind: "SContinue", pos: pos};
			case SSwitch(_, _, _, pos): {kind: "SSwitch", pos: pos};
			case SReturnVoid(pos): {kind: "SReturnVoid", pos: pos};
			case SReturn(_, pos): {kind: "SReturn", pos: pos};
			case SExpr(_, pos): {kind: "SExpr", pos: pos};
		}
		final pos = kindAndPos.pos;
		final line = pos == null ? 0 : pos.getLine();
		final col = pos == null ? 0 : pos.getColumn();
		traceStage3Phase("stmt_list_" + phase + ":" + fn + ":" + idx + "/" + total + ":" + kindAndPos.kind + ":line=" + line + ":col=" + col);
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

private class _LocalTyEntry {
	public final name:String;
	public final ty:String;

	public function new(name:String, ty:String) {
		this.name = name;
		this.ty = ty;
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
	static var currentFunctionName:Null<String> = null;
	static var currentFunctionLocalTypeHints:Null<Map<String, TyType>> = null;
	static var currentStmtTyEntries:Array<_LocalTyEntry> = [];
	static var currentLocalCallSigCache:Null<Map<String, EmitterCallSig>> = null;

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

	static var currentPortableMetalizationRegionKey:String = "";

	public static function installPortableMetalizationPlan(plan:Null<backend.ocaml.PortableMetalizationPlan>):_PortableMetalizationScope {
		_EmitterStageDebug.traceStage3Phase("portable_plan_install");
		final scope = new _PortableMetalizationScope(currentPortableMetalizationPlan, currentPortableMetalizationRegionKey);
		currentPortableMetalizationPlan = plan;
		currentPortableMetalizationRegionKey = "";
		return scope;
	}

	public static function restorePortableMetalizationPlan(scope:_PortableMetalizationScope):Void {
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
			&& currentPortableMetalizationRegionKey.length > 0
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
			?portableMetalizationPlan:backend.ocaml.PortableMetalizationPlan):String {
		_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_before_install");
		final scope = installPortableMetalizationPlan(portableMetalizationPlan);
		var entryPath = "";
		try {
			_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_before_emitToDir");
			entryPath = emitToDir(p, outDir, emitFullBodies, buildExecutable, ocamlProfile);
			_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_after_emitToDir");
		} catch (error:haxe.io.Error) {
			_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_catch_io_error");
			restorePortableMetalizationPlan(scope);
			throw error;
		} catch (error:String) {
			_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_catch_string");
			restorePortableMetalizationPlan(scope);
			throw error;
		} catch (error:haxe.Exception) {
			_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_catch_haxe_exception");
			restorePortableMetalizationPlan(scope);
			throw error;
		}
		restorePortableMetalizationPlan(scope);
		_EmitterStageDebug.traceStage3Phase("portable_plan_wrapper_after_restore");
		return entryPath;
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

	/** Force a value through an erased boundary where Stage3 helper signatures are still Obj.t-based. */
	static function eraseBoundary<TIn, TOut>(value:TIn):TOut {
		return cast value;
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
		- Do not treat plain trailing dynamic-element array parameters as variadics.

		Why this restriction matters
		- Upstream reflection APIs like `Type.createInstance(cl, args)` and
		  `Reflect.callMethod(obj, func, args)` take a normal array argument.
		- Misclassifying those as rest parameters silently wraps the supplied array one
		  level deeper at call sites, which then fails OCaml typechecking.
	**/
	static inline function isRestLikeArg(arg:HxFunctionArg):Bool {
		if (arg == null)
			return false;
		if (HxFunctionArg.getIsRest(arg))
			return true;
		final hint = StringTools.trim(HxFunctionArg.getTypeHint(arg));
		return hint == "Rest"
			|| StringTools.startsWith(hint, "Rest<")
			|| StringTools.startsWith(hint, "haxe.Rest<")
			|| StringTools.startsWith(hint, "haxe.extern.Rest<");
	}

	static function exprToOcamlString(e:HxExpr, ?tyByIdent:Map<String, TyType>, ?arityByIdent:Map<String, Int>, ?staticImportByIdent:Map<String, String>,
			?currentPackagePath:String, ?moduleNameByPkgAndClass:Map<String, String>, ?callSigByCallee:Map<String, EmitterCallSig>):String {
		final tyByIdentRaw = tyByIdent;

		function tyLookup(name:String):Null<TyType> {
			return cast mapGetRaw(tyByIdentRaw, name);
		}

		function stmtTyLookup(name:String):String {
			if (name == null || name.length == 0)
				return "";
			for (entry in currentStmtTyEntries)
				if (entry.name == name && entry.ty != null && entry.ty.length > 0)
					return entry.ty;
			final lowered = ocamlValueIdent(name);
			if (lowered != name)
				for (entry in currentStmtTyEntries)
					if (entry.name == lowered && entry.ty != null && entry.ty.length > 0)
						return entry.ty;
			return "";
		}

		function localHintLookup(name:String):Null<TyType> {
			return cast mapGetRaw(cast currentFunctionLocalTypeHints, name);
		}

		inline function resolveTyIdentName(name:String):String {
			if (tyLookup(name) != null)
				return name;
			final lowered = ocamlValueIdent(name);
			return lowered != name && tyLookup(lowered) != null ? lowered : name;
		}

		function tyForIdent(name:String):String {
			final t = tyLookup(resolveTyIdentName(name));
			final ts = t == null ? "" : t.toString();
			final shouldUseLocalHint = t == null || ts.length == 0 || ts == "Dynamic" || ts == "Unknown" || ts == "Array";
			if (shouldUseLocalHint) {
				final stmtTy = stmtTyLookup(name);
				if (stmtTy.length > 0 && stmtTy != "Dynamic" && stmtTy != "Unknown" && stmtTy != "Array")
					return stmtTy;
				if (currentFunctionLocalTypeHints != null) {
					final hinted = localHintLookup(name);
					if (hinted != null) {
						final hintedS = hinted.toString();
						if (hintedS.length > 0 && hintedS != "Dynamic" && hintedS != "Unknown" && hintedS != "Array")
							return hintedS;
					}
					final lowered = ocamlValueIdent(name);
					if (lowered != name) {
						final loweredHint = localHintLookup(lowered);
						if (loweredHint != null) {
							final loweredHintS = loweredHint.toString();
							if (loweredHintS.length > 0 && loweredHintS != "Dynamic" && loweredHintS != "Unknown" && loweredHintS != "Array")
								return loweredHintS;
						}
					}
				}
			}
			return ts;
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
				case EFloat(v): "string_of_float " + Std.string(v);
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

	static function staticImportModuleForStage3(name:String, ?staticImportByIdent:Map<String, String>):String {
		final resolved = mapGetRaw(staticImportByIdent, name);
		if (resolved != null)
			return cast resolved;
		final globalResolved = mapGetRaw(currentGlobalImportAliasByIdent, name);
		return globalResolved == null ? null : cast globalResolved;
	}

	static function moduleNameForStage3Key(key:String, ?moduleNameByPkgAndClass:Map<String, String>):String {
		final resolved = mapGetRaw(moduleNameByPkgAndClass, key);
		if (resolved != null)
			return cast resolved;
		for (entry in currentModuleNameEntries)
			if (entry.key == key)
				return entry.moduleName;
		return null;
	}

	static function isKnownModuleNameForStage3(name:String):Bool {
		return currentKnownModuleNames != null && currentKnownModuleNames.exists(name);
	}

	static function currentModuleShortNameForStage3(?currentPackagePath:String):String {
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

	static function extendTyByIdentForStage3<TTy>(ty:TTy, name:String, t:TyType):Map<String, TyType> {
		final out = new Map<String, TyType>();
		final keys = mapKeysRaw(ty);
		if (keys != null)
			for (k in keys) {
				final existing = mapGetRaw(ty, k);
				if (existing != null)
					out.set(k, existing);
			}
		out.set(name, t);
		return out;
	}

	static function extendTyByIdentManyForStage3<TTy>(ty:TTy, names:Array<String>, t:TyType):Map<String, TyType> {
		final out = new Map<String, TyType>();
		final keys = mapKeysRaw(ty);
		if (keys != null)
			for (k in keys) {
				final existing = mapGetRaw(ty, k);
				if (existing != null)
					out.set(k, existing);
			}
		if (names != null)
			for (name in names)
				out.set(name, t);
		return out;
	}

	/**
		Why:
		Static/module field access is a large hot branch while Stage3 full-emits
		this emitter. Keeping the package-walk logic out of the local `EField`
		case reduces the body shape the bootstrap emitter has to lower.

		What:
		Returns OCaml for `<type path>.field` access when the receiver is known to
		be a static/module path. Returns `null` for normal instance-field fallback.

		How:
		This mirrors the previous local resolution order: static imports first,
		then module-local helper providers, then package-relative type-path lookup
		with the existing same-package fallback and Int64 import override.
	**/
	static function tryExprToOcamlStage3StaticField(obj:HxExpr, field:String, ?staticImportByIdent:Map<String, String>, ?currentPackagePath:String,
			?moduleNameByPkgAndClass:Map<String, String>):Null<String> {
		switch (obj) {
			case EIdent(typeName):
				final importedModule = staticImportModuleForStage3(typeName, staticImportByIdent);
				if (importedModule != null && importedModule.length > 0) {
					return (currentOcamlModuleName != null
						&& importedModule == currentOcamlModuleName) ? ocamlValueIdent(field) : (importedModule + "." + ocamlValueIdent(field));
				}
				if (currentOcamlModuleName != null && isUpperStart(typeName)) {
					final inCurrentModule = currentInstanceFieldsFor(typeName) != null || currentInstanceMethodsFor(typeName) != null;
					if (inCurrentModule && typeName != currentModuleShortNameForStage3(currentPackagePath)) {
						final localHelperModule = currentOcamlModuleName + "_" + typeName;
						return localHelperModule + "." + ocamlValueIdent(field);
					}
				}
			case _:
		}

		final parts = tryExtractTypePathPartsFromExpr(obj);
		if (parts == null || parts.length == 0 || !isUpperStart(parts[parts.length - 1]))
			return null;

		var modName = ocamlModuleNameFromTypePathParts(parts);
		var resolvedByModuleIndex = false;
		if (moduleNameByPkgAndClass != null) {
			final raw = parts.join(".");
			var cur = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
			while (true) {
				final key = cur + ":" + raw;
				final local = moduleNameForStage3Key(key, moduleNameByPkgAndClass);
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
				&& !isKnownModuleNameForStage3(modName)
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
		if (parts.length == 1 && parts[0] == "Int64" && currentImportInt64 != null && currentImportInt64.length > 0) {
			modName = currentImportInt64;
		}
		return (currentOcamlModuleName != null && modName == currentOcamlModuleName) ? ocamlValueIdent(field) : (modName + "." + ocamlValueIdent(field));
	}

	/**
		Why:
		Array-comprehension lowering is independent from `exprToOcaml`'s local type
		predicates but previously lived directly in the already-large expression
		switch. Pulling it out keeps the self-emitted expression body smaller.

		What:
		Lowers the small Stage3-supported subset of Haxe array comprehensions:
		range loops and array-like iterables that append each yielded value.

		How:
		The loop variable is added to a cloned type context before lowering the
		yield expression, preserving the old local branch behavior.
	**/
	static function exprToOcamlArrayComprehension(name:String, iterable:HxExpr, yieldExpr:HxExpr, ?arityByIdent:Map<String, Int>,
			?tyByIdent:Map<String, TyType>, ?staticImportByIdent:Map<String, String>, ?currentPackagePath:String,
			?moduleNameByPkgAndClass:Map<String, String>, ?callSigByCallee:Map<String, EmitterCallSig>):String {
		final out = "__arr_comp_out";
		final v = ocamlValueIdent(name);
		final loopTy = switch (iterable) {
			case ERange(_, _):
				TyType.fromHintText("Int");
			case _:
				TyType.fromHintText("Dynamic");
		};
		final ty2 = extendTyByIdentForStage3(cast tyByIdent, name, loopTy);
		final body = exprToOcaml(yieldExpr, arityByIdent, ty2, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
		return switch (iterable) {
			case ERange(startExpr, endExpr):
				final start = exprToOcaml(startExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
					callSigByCallee);
				final end = exprToOcaml(endExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
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
	}

	/**
		Why:
		Bare identifier lowering sits directly on the current hxhx-full-emit hot path
		while this emitter self-emits. Keeping the branch body in a static helper
		reduces the expression switch shape without changing identifier semantics.

		What:
		Lowers one `EIdent` using caller-computed context predicates. The helper
		distinguishes bound method captures, locals, static methods, static imports,
		uppercase value/type names, and final bring-up poison fallback.

		How:
		The caller owns context-sensitive lookups such as local type maps and mutable
		ref tracking; this helper only applies the established precedence order and
		emits the same OCaml snippets as the former inline switch branch.
	**/
	static function exprToOcamlIdentStage3(name:String, hasCurrentInstanceMethod:Bool, hasThisBinding:Bool, hasTyIdent:Bool, isMutableLocalRef:Bool,
			hasArity:Bool, staticImportModule:String):String {
		if (hasCurrentInstanceMethod && hasThisBinding) {
			return ocamlValueIdent(name) + " (this_)";
		}
		if (hasTyIdent || isMutableLocalRef) {
			return ocamlReadValueIdent(name);
		}
		if (hasArity) {
			return ocamlValueIdent(name);
		}
		if (staticImportModule != null) {
			return staticImportModule + "." + ocamlValueIdent(name);
		}
		if (isUpperStart(name)) {
			return "(Obj.magic 0)";
		}
		return "(Obj.magic 0)";
	}

	/**
		Why:
		`ENew` lowering is another bulky expression-switch branch encountered while
		Stage3 emits this file. Pulling it out keeps the self-emitted `exprToOcaml`
		body smaller and avoids adding another generated-OCaml patch seam.

		What:
		Lowers the current Stage3-supported allocation subset: empty arrays,
		`sys.io.Process`, and best-effort construction of current-module anonymous
		object records with optional constructor invocation.

		How:
		Runtime-backed constructors use dedicated shims. Current-module class-like
		constructors allocate `HxAnon`, initialize declared fields to null, then call
		the generated `new` method when present, preserving the previous inline order.
	**/
	static function exprToOcamlNewStage3(typePath:String, args:Array<HxExpr>, ?arityByIdent:Map<String, Int>, ?tyByIdent:Map<String, TyType>,
			?staticImportByIdent:Map<String, String>, ?currentPackagePath:String, ?moduleNameByPkgAndClass:Map<String, String>,
			?callSigByCallee:Map<String, EmitterCallSig>):String {
		if (typePath == "Array" && args.length == 0) {
			return "HxBootArray.create ()";
		}
		if ((typePath == "sys.io.Process" || typePath == "sys.io.Process.Process") && (args.length == 2 || args.length == 3)) {
			return "HxBootProcess.spawn ("
				+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ") ("
				+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ")";
		}
		final fields = currentInstanceFieldsFor(typePath);
		if (fields == null)
			return "(Obj.magic 0)";
		final ctorMethods = currentInstanceMethodsFor(typePath);
		final ctorName = ocamlValueIdent("new");
		final argCodes = args.map(a -> "("
			+ exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
			+ ")");
		final ctorCall = hasMethodName(ctorMethods,
			"new") ? ("ignore (" + ctorName + " (__hx_obj)" + (argCodes.length == 0 ? "" : (" " + argCodes.join(" "))) + ")") : "()";
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
	}

	/**
		Why:
		The Stage3 full-emit trace repeatedly lands in the large core-intrinsic
		cluster inside `exprToOcaml`. These rewrites do not need the caller's local
		type predicates, so they can live outside the main expression switch.

		What:
		Handles bring-up-only `Reflect`/`Type`, narrow `StringTools`, `Std`, common
		extension filesystem calls, and basic print intrinsics. Returns `null` when
		normal expression lowering must continue.

		How:
		The helper preserves the old branch order and delegates recursive operands
		back through `exprToOcaml` / `exprToOcamlString` with the same context maps.
	**/
	static function tryExprToOcamlStage3CoreIntrinsic(e:HxExpr, ?arityByIdent:Map<String, Int>, ?tyByIdent:Map<String, TyType>,
			?staticImportByIdent:Map<String, String>, ?currentPackagePath:String, ?moduleNameByPkgAndClass:Map<String, String>,
			?callSigByCallee:Map<String, EmitterCallSig>):Null<String> {
		switch (e) {
			case ECall(EField(EIdent("Math"), "isNaN"), [arg]):
				return "(classify_float ("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") = FP_nan)";
			case ECall(EField(EIdent("Math"), "isFinite"), [arg]):
				return "(match classify_float ("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") with | FP_nan | FP_infinite -> false | _ -> true)";
			case ECall(EField(EIdent("Math"), "isInfinite"), [arg]):
				return "(classify_float ("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") = FP_infinite)";
			case ECall(EField(EIdent("Std"), "isOfType"), [valueExpr, typeExpr]):
				return "Std.isOfType ("
					+ exprToOcaml(valueExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") (Obj.repr ("
					+ exprToOcaml(typeExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ "))";
			case ECall(EField(EIdent("Array"), "wrap"), [arg]):
				return "(Obj.magic (" + exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + "))";
			case EField(EIdent("String"), "fromCharCode"):
				return "(fun i -> Stdlib.String.make 1 (Char.chr i))";
			case ECall(EField(EIdent("Math"), "pow"), [_a, _b]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Math"), "floor"), [_arg]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Math"), "log"), [_arg]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Math"), "fround"), [_arg]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Timer"), "stamp"), []):
				return "(Unix.gettimeofday ())";
			case ECall(EField(EIdent("Int64"), "ofInt"), [arg]) | ECall(EField(EIdent("haxe.Int64"), "ofInt"), [arg]):
				return "Haxe_Int64.ofInt ("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")";
			case ECall(EField(EIdent("Int64"), "make"), [lo, hi]) | ECall(EField(EIdent("haxe.Int64"), "make"), [lo, hi]):
				return "Haxe_Int64.make ("
					+ exprToOcaml(lo, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") ("
					+ exprToOcaml(hi, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")";
			case ELambda(args, body):
				final ocamlArgs = args.map(ocamlValueIdent).join(" ");
				final ty2 = extendTyByIdentManyForStage3(cast tyByIdent, args, TyType.fromHintText("Dynamic"));
				return "(fun "
					+ (ocamlArgs.length == 0 ? "_" : ocamlArgs)
					+ " -> "
					+ exprToOcaml(body, arityByIdent, ty2, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")";
			case ETryCatchRaw(_raw):
				return "(Obj.magic 0)";
			case EField(EIdent("Math"), "NaN"):
				return "nan";
			case EField(EIdent("Math"), "POSITIVE_INFINITY"):
				return "infinity";
			case EField(EIdent("Math"), "NEGATIVE_INFINITY"):
				return "neg_infinity";
			case EField(EIdent("Math"), "PI"):
				return "(4.0 *. atan 1.0)";
			case ECall(EField(EIdent("Reflect"), "fields"), [_obj]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "field"), [_obj, _name]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "getProperty"), [_obj, _name]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "setProperty"), [_obj, _name, _value]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Reflect"), "hasField"), [_obj, _name]):
				return "false";
			case ECall(EField(EIdent("Reflect"), "isFunction"), [_obj]):
				return "true";
			case ECall(EField(EIdent("Type"), "getClass"), [_obj]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Type"), "getInstanceFields"), [_cls]):
				return "(Obj.magic 0)";
			case ECall(EField(EIdent("Type"), "getClassName"), [_cls]):
				return escapeOcamlString("");
			case ECall(EField(EIdent("Type"), "getEnumName"), [_enm]):
				return escapeOcamlString("");
			case ECall(EField(EIdent("Type"), "typeof"), [_v]):
				return "(Obj.magic 0)";
			case ECall(EField(_obj, "set_low"), [_v]):
				return "()";
			case ECall(EField(_obj, "set_high"), [_v]):
				return "()";
			case ECall(EField(EIdent("StringTools"), "fastCodeAt"), [s, idx]) | ECall(EField(EIdent("StringTools"), "unsafeCodeAt"), [s, idx]):
				final s2 = exprToOcaml(s, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				final i2 = exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				return "(let __s = ("
					+ s2
					+ ") in "
					+ "let __i = ("
					+ i2
					+ ") in "
					+ "if (__i < 0) || (__i >= Stdlib.String.length __s) then (-1) else (Char.code (Stdlib.String.get __s __i)))";
			case ECall(EField(EIdent("StringTools"), "hex"), [n]):
				return "StringTools.hex ("
					+ exprToOcaml(n, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ") (0)";
			case ECall(EField(EIdent("StringTools"), "replace"), [_s, _sub, _by]):
				return escapeOcamlString("");
			case ECall(EField(EIdent("Std"), "is"), [_v, _t]):
				return "true";
			case ECall(EField(EIdent("Std"), "string"), [arg]):
				return "Std.string (Obj.repr ("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ "))";
			case ECall(EField(EIdent("Std"), "downcast"), [_value, _cls]):
				return "(Obj.magic HxRuntime.hx_null)";
			case ECall(EField(_obj, "exists"), []):
				return "true";
			case ECall(EField(_obj, "readDirectory"), []):
				return "(Obj.magic 0)";
			case ECall(EField(_obj, "isDirectory"), []):
				return "false";
			case ECall(EIdent("trace"), [arg]):
				return "print_endline ("
					+ exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ")";
			case ECall(EField(EIdent("Sys"), "println"), [arg]):
				return "print_endline ("
					+ exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ")";
			case ECall(EField(EIdent("Sys"), "print"), [arg]):
				return "print_string ("
					+ exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ")";
			case _:
		}
		return null;
	}

	/**
		Why:
		Stage3 full-body emission lowers this source file with the current committed
		bootstrap compiler, so large local switch bodies inside `exprToOcaml` become
		a direct bootstrap cost. These early runtime intrinsics are independent of
		the local expression-lowering closures, which makes them safe to keep in a
		plain static helper.

		What:
		Returns OCaml for known Stage3 bring-up calls backed by repo-owned runtime
		shims, or `null` when normal expression lowering should continue.

		How:
		Keep this helper limited to cases that do not depend on `exprToOcaml`'s
		local type predicates. Cases that need local statement/type context stay in
		the caller so behavior does not change.
	**/
	static function tryExprToOcamlStage3RuntimeIntrinsic(callee:HxExpr, args:Array<HxExpr>, ?arityByIdent:Map<String, Int>, ?tyByIdent:Map<String, TyType>,
			?staticImportByIdent:Map<String, String>, ?currentPackagePath:String, ?moduleNameByPkgAndClass:Map<String, String>,
			?callSigByCallee:Map<String, EmitterCallSig>):Null<String> {
		switch (callee) {
			// Upstream `tests/runci/Config.hx` declares `macro function isCi()` and uses it in
			// runtime code. Real Haxe expands it to a constant; Stage3 approximates it as the
			// same GitHub Actions environment probe used by the upstream helper.
			case EIdent("isCi") if (args.length == 0):
				return "((match Stdlib.Sys.getenv_opt \"GITHUB_ACTIONS\" with | Some v -> v | None -> \"\") = \"true\")";
			case EField(EIdent("Config"), "isCi") if (args.length == 0):
				return "((match Stdlib.Sys.getenv_opt \"GITHUB_ACTIONS\" with | Some v -> v | None -> \"\") = \"true\")";
			case EField(EIdent("runci.Config"), "isCi") if (args.length == 0):
				return "((match Stdlib.Sys.getenv_opt \"GITHUB_ACTIONS\" with | Some v -> v | None -> \"\") = \"true\")";

			// Stage3 emit-runner bring-up: map `sys.FileSystem` statics used by RunCi to the
			// repo-owned OCaml runtime implementation.
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

			// Stage3 emit-runner bring-up: map `sys.io.File` statics used by RunCi targets to
			// the repo-owned OCaml runtime implementation.
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

			// Gate2 bring-up: avoid depending on the std `Xml` implementation while still
			// compiling upstream harness code that parses remote appcasts.
			case EField(EIdent("Xml"), "parse") if (args.length == 1):
				return "(Obj.magic 0)";

			// Path helpers used by upstream RunCi config and Flash harness paths.
			case EField(EIdent("Path"), "join") if (args.length == 1):
				return "HxBootArray.join ("
					+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") (\"/\") (fun (s : string) -> s)";
			case EField(EIdent("Path"), "normalize") if (args.length == 1):
				return "HxFileSystem.normalize_path ("
					+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ")";
			case EField(EIdent("Path"), "directory") if (args.length == 1):
				return "Filename.dirname ("
					+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ")";
			case _:
		}
		return null;
	}

	static function exprToOcaml(e:HxExpr, ?arityByIdent:Map<String, Int>, ?tyByIdent:Map<String, TyType>, ?staticImportByIdent:Map<String, String>,
			?currentPackagePath:String, ?moduleNameByPkgAndClass:Map<String, String>, ?callSigByCallee:Map<String, EmitterCallSig>):String {
		final tyByIdentRaw = tyByIdent;
		final arityByIdentRaw = arityByIdent;
		final staticImportByIdentRaw = staticImportByIdent;
		final moduleNameByPkgAndClassRaw = moduleNameByPkgAndClass;
		final callSigByCalleeRaw = callSigByCallee;

		function tyLookup(name:String):Null<TyType> {
			return cast mapGetRaw(tyByIdentRaw, name);
		}

		function stmtTyLookup(name:String):String {
			if (name == null || name.length == 0)
				return "";
			for (entry in currentStmtTyEntries)
				if (entry.name == name && entry.ty != null && entry.ty.length > 0)
					return entry.ty;
			final lowered = ocamlValueIdent(name);
			if (lowered != name)
				for (entry in currentStmtTyEntries)
					if (entry.name == lowered && entry.ty != null && entry.ty.length > 0)
						return entry.ty;
			return "";
		}

		function localHintLookup(name:String):Null<TyType> {
			return cast mapGetRaw(cast currentFunctionLocalTypeHints, name);
		}

		inline function resolveTyIdentName(name:String):String {
			if (tyLookup(name) != null)
				return name;
			final lowered = ocamlValueIdent(name);
			return lowered != name && tyLookup(lowered) != null ? lowered : name;
		}

		inline function hasTyIdent(name:String):Bool {
			return tyLookup(resolveTyIdentName(name)) != null;
		}

		inline function hasThisBinding():Bool {
			return hasTyIdent("this") || hasTyIdent("this_");
		}

		inline function hasArity(name:String):Bool {
			return mapHasRaw(arityByIdentRaw, name);
		}

		inline function arityFor(name:String):Int {
			final resolved = mapGetRaw(arityByIdentRaw, name);
			if (resolved == null)
				return 0;
			final arity:Int = cast resolved;
			return arity;
		}

		inline function staticImportModule(name:String):String {
			final resolved = mapGetRaw(staticImportByIdentRaw, name);
			if (resolved != null)
				return cast resolved;
			final globalResolved = mapGetRaw(currentGlobalImportAliasByIdent, name);
			return globalResolved == null ? null : cast globalResolved;
		}

		inline function isKnownModuleName(name:String):Bool {
			return currentKnownModuleNames != null && currentKnownModuleNames.exists(name);
		}

		function moduleNameForKey(key:String):String {
			final resolved = mapGetRaw(moduleNameByPkgAndClassRaw, key);
			if (resolved != null)
				return cast resolved;
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
			final resolved = mapGetRaw(callSigByCalleeRaw, callee);
			return resolved == null ? null : cast resolved;
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
			final t = tyLookup(resolveTyIdentName(name));
			final ts = t == null ? "" : t.toString();
			final shouldUseLocalHint = t == null || ts.length == 0 || ts == "Dynamic" || ts == "Unknown" || ts == "Array";
			if (shouldUseLocalHint) {
				final stmtTy = stmtTyLookup(name);
				if (stmtTy.length > 0 && stmtTy != "Dynamic" && stmtTy != "Unknown" && stmtTy != "Array")
					return stmtTy;
				if (currentFunctionLocalTypeHints != null) {
					final hinted = localHintLookup(name);
					if (hinted != null) {
						final hintedS = hinted.toString();
						if (hintedS.length > 0 && hintedS != "Dynamic" && hintedS != "Unknown" && hintedS != "Array")
							return hintedS;
					}
					final lowered = ocamlValueIdent(name);
					if (lowered != name) {
						final loweredHint = localHintLookup(lowered);
						if (loweredHint != null) {
							final loweredHintS = loweredHint.toString();
							if (loweredHintS.length > 0 && loweredHintS != "Dynamic" && loweredHintS != "Unknown" && loweredHintS != "Array")
								return loweredHintS;
						}
					}
				}
			}
			return ts;
		}

		inline function readIdent(name:String):String {
			return ocamlReadValueIdent(name);
		}

		inline function isInt64TypeName(t:String):Bool {
			if (t == null)
				return false;
			final trimmed = StringTools.trim(t);
			if (trimmed.length == 0)
				return false;
			return trimmed == "haxe.Int64"
				|| trimmed == "Int64"
				|| StringTools.endsWith(trimmed, ".Int64")
				|| StringTools.endsWith(trimmed, "_Int64")
				|| trimmed.indexOf("Int64") >= 0;
		}

		function isInt64Expr(expr:HxExpr):Bool {
			return switch (expr) {
				case EIdent(name):
					isInt64TypeName(tyForIdent(name));
				case EUnop("!", inner):
					isInt64Expr(inner);
				case ECall(EField(EIdent(owner), field), _args): (owner == "Int64" || owner == "haxe.Int64") && (field == "make" || field == "ofInt"
						|| field == "parseString" || field == "add" || field == "sub" || field == "mul" || field == "neg" || field == "div" || field == "mod"
						|| field == "divMod");
				case EField(inner, field): isInt64Expr(inner) && (field == "high" || field == "low" || field == "quotient" || field == "modulus");
				case EBinop(op, a, b)
					if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%" || op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>"
						|| op == ">>>"): isInt64Expr(a) || isInt64Expr(b);
				case ETernary(_cond, thenExpr, elseExpr): isInt64Expr(thenExpr) && isInt64Expr(elseExpr);
				case ECast(inner, _):
					isInt64Expr(inner);
				case EUntyped(inner):
					isInt64Expr(inner);
				case _:
					false;
			}
		}

		function isIntExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EInt(_):
					true;
				case EIdent(name): final t = tyForIdent(name); t == "Int" || (isMutableLocalRefIdent(name)
						&& (t == "" || t == "Dynamic" || t == "Unknown"));
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
				case EIdent(name): final t = tyForIdent(name); t == "" || t == "Dynamic" || t == "Unknown" || t == "Array" || isMutableLocalRefIdent(name);
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
					!(isInt64Expr(a) || isInt64Expr(b)) && (isFloatExpr(a) || isFloatExpr(b) || (isIntExpr(a) && isIntExpr(b)));
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

		function isNullableIntExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case ENull:
					true;
				case ECall(EField(EIdent("Std"), "parseInt"), [_]):
					true;
				case ETernary(_cond, thenExpr, elseExpr): isNullableIntExpr(thenExpr) || isNullableIntExpr(elseExpr);
				case _:
					false;
			}
		}

		function exprToOcamlNullableInt(expr:HxExpr):String {
			return switch (expr) {
				case ENull:
					"HxRuntime.hx_null";
				case EInt(_):
					"Obj.repr (" + exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
						callSigByCallee) + ")";
				case _:
					exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
			}
		}

		inline function emitUnknownLength(o:String):String {
			// Reuse the bound `Obj.t` for dynamic casts instead of re-emitting `o`.
			// This matters when `o` is the bring-up placeholder `(Obj.magic 0)`: re-emitting it
			// under a cast can make OCaml infer the placeholder argument itself as `Obj.t`.
			return "(let __hx_len_obj = Obj.repr ("
				+ o
				+ ") in "
				+ "if Obj.is_int __hx_len_obj then HxBootArray.length ((Obj.obj __hx_len_obj : _ HxBootArray.t)) "
				+ "else if Obj.tag __hx_len_obj = Obj.string_tag then HxString.length ((Obj.obj __hx_len_obj : string)) "
				+ "else HxBootArray.length ((Obj.obj __hx_len_obj : _ HxBootArray.t)))";
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
					isLikelyArrayExpr(inner);
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

		/** Keep the bootstrap/stage0 call boundary erased here so callers stay typed and generated ML stops wrapping map args with `Obj.repr`. */
		function extendTyByIdent<TTy>(ty:TTy, name:String, t:TyType):Map<String, TyType> {
			final out = new Map<String, TyType>();
			final keys = mapKeysRaw(ty);
			if (keys != null)
				for (k in keys) {
					final existing = mapGetRaw(ty, k);
					if (existing != null)
						out.set(k, existing);
				}
			out.set(name, t);
			return out;
		}

		/** Keep the bootstrap/stage0 call boundary erased here so callers stay typed and generated ML stops wrapping map args with `Obj.repr`. */
		function extendTyByIdentMany<TTy>(ty:TTy, names:Array<String>, t:TyType):Map<String, TyType> {
			final out = new Map<String, TyType>();
			final keys = mapKeysRaw(ty);
			if (keys != null)
				for (k in keys) {
					final existing = mapGetRaw(ty, k);
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

		final coreIntrinsic = tryExprToOcamlStage3CoreIntrinsic(e, arityByIdentRaw, tyByIdentRaw, staticImportByIdentRaw, currentPackagePath,
			moduleNameByPkgAndClassRaw, callSigByCalleeRaw);
		if (coreIntrinsic != null)
			return coreIntrinsic;

		return switch (e) {
			case ECall(EField(EIdent("Math"), "abs"), [arg]):
				// Best-effort numeric abs. Prefer float when the expression looks float-typed.
				(isFloatExpr(arg) ? "abs_float " : (isIntExpr(arg) ? "abs " : "abs_float "))
					+ "("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")";
			case ECall(EField(EIdent("Math"), "round"), [arg]):
				// Bring-up: good-enough rounding for positive values (used by RunCi timing logs).
				//
				// NOTE: Haxe's `Math.round` handles negatives differently; for Gate bring-up the
				// upstream harness uses `Timer.stamp()` deltas which are non-negative.
				"(int_of_float (floor ((" + exprToOcamlAsFloatValue(arg) + ") +. 0.5)))";
			case ELambda(_, _), ETryCatchRaw(_):
				// Exhaustiveness fallback; normal handling returns from the pre-switch intrinsic helper.
				"(Obj.magic 0)";

			case ECall(EField(obj, "toString"), []) if (isStringExpr(obj)):
				// Bring-up: in Haxe, `String.toString()` is an identity; mapping this avoids
				// poisoning common patterns like `input.readAll().toString()`.
				exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);

			case EBool(v): v ? "true" : "false";
			case EInt(v): Std.string(v);
			case EFloat(v): Std.string(v);
			case EString(v): escapeOcamlString(v);
			case EIdent(name):
				exprToOcamlIdentStage3(name, hasCurrentInstanceMethod(name), hasThisBinding(), hasTyIdent(name), isMutableLocalRefIdent(name), hasArity(name),
					staticImportModule(name));
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
				exprToOcamlNewStage3(typePath, args, arityByIdentRaw, tyByIdentRaw, staticImportByIdentRaw, currentPackagePath, moduleNameByPkgAndClassRaw,
					callSigByCalleeRaw);
			case EArrayComprehension(name, iterable, yieldExpr):
				exprToOcamlArrayComprehension(name, iterable, yieldExpr, arityByIdentRaw, tyByIdentRaw, staticImportByIdentRaw, currentPackagePath,
					moduleNameByPkgAndClassRaw, callSigByCalleeRaw);
			case EField(obj, field):
				// Stage 3 bring-up: model a couple of common "instance field" shapes that appear in
				// orchestration code, without committing to a full object layout/runtime.
				//
				// - Array.length (via the bootstrap `HxBootArray` shim)
				// - String.length (via the runtime `HxString` shim)
				if (field == "length") {
					final o = exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					if (isStringExpr(obj)) {
						return "HxString.length (" + o + ")";
					}
					switch (obj) {
						case EArrayDecl(_):
							return "HxBootArray.length (" + o + ")";
						case EIdent(name):
							final t = tyForIdent(name);
							if (t == "String")
								return "HxString.length (" + o + ")";
							if (StringTools.startsWith(t, "Array<"))
								return "HxBootArray.length (" + o + ")";
							return emitUnknownLength(o);
						case _:
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

				final staticField = tryExprToOcamlStage3StaticField(obj, field, staticImportByIdentRaw, currentPackagePath, moduleNameByPkgAndClassRaw);
				staticField != null ? staticField : ("(Obj.magic (HxAnon.get (Obj.repr ("
					+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ")) "
					+ escapeOcamlString(field)
					+ "))");
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

				final runtimeIntrinsic = tryExprToOcamlStage3RuntimeIntrinsic(callee, args, arityByIdentRaw, tyByIdentRaw, staticImportByIdentRaw,
					currentPackagePath, moduleNameByPkgAndClassRaw, callSigByCalleeRaw);
				if (runtimeIntrinsic != null)
					return runtimeIntrinsic;

				// Special-case a tiny slice of runtime I/O so bring-up server binaries can function
				// before the full runtime is modeled. Cases that need local type predicates stay here.
				switch (callee) {
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
					case EField(EIdent("StringTools"), "trim") if (args.length == 1):
						return "Stdlib.String.trim ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
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
					case EField(obj, "map") if (args.length == 1):
						// Stage3 emit-runner: treat array `map` calls as runtime intrinsics so
						// OCaml sees a direct function call instead of dynamic-field invocation
						// with warning-as-error over-application.
						if (isLikelyArrayExpr(obj)) {
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
						if (isLikelyArrayExpr(obj)) {
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
					case _:
						null;
				};

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

				final c = if (instanceCallName != null) {
					if (receiverAlreadyForwarded) {
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
				if (c == "getString" && args.length == 2) {
					return c
						+ " (this_)"
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

					function callSigForExpr(expr:HxExpr):Null<EmitterCallSig> {
						return switch (expr) {
							case EIdent(name):
								final lowered = ocamlValueIdent(name);
								final byLowered = callSigFor(lowered);
								byLowered != null ? byLowered : callSigFor(name);
							case EField(obj, name):
								final lowered = ocamlValueIdent(name);
								final byLowered = callSigFor(lowered);
								if (byLowered != null) {
									byLowered;
								} else {
									final byName = callSigFor(name);
									if (byName != null) {
										byName;
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
												if (moduleNameByPkgAndClassRaw != null) {
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
						if (currentLocalCallSigCache == null) {
							final cache:Map<String, EmitterCallSig> = new Map();
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
										final sig = callSigFromFunction(fn);
										cache.set(fnNameRaw, sig);
										cache.set(ocamlValueIdent(fnNameRaw), sig);
									}
								}
							} catch (_:haxe.Exception) {} catch (_:String) {}
							currentLocalCallSigCache = cache;
						}
						final cached = currentLocalCallSigCache.get(name);
						if (cached != null)
							return cached;
						return null;
					}

					var sig = callSigFor(c);
					if (sig == null && !receiverPreApplied) {
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
					if (sig != null && !sig.hasRest && args.length > sig.expected) {
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
					if (hasArity(c) && args.length > arityFor(c)) {
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
						final forceImplicitThis = switch (callee) {
							case EIdent(name): hasThisBinding() && hasArity(name) && (args.length + 1) == arityFor(name);
							case EField(EThis, name): hasArity(name) && (args.length + 1) == arityFor(name);
							case _:
								false;
						};
						if (forceImplicitThis && c.indexOf(" (this_)") == -1)
							fullArgs.insert(0, EThis);

						// Stage3 widened-closure hardening: some recovered call signatures include an
						// implicit receiver parameter (`this_` + args). If a call-site provides fewer
						// args than the receiver-aware signature requires, prepend the receiver explicitly.
						//
						// - In instance contexts, forward `this`.
						// - Outside instance contexts (for static/qualified call-shapes), use a sentinel.
						if (sig != null && sig.needsReceiver && fullArgs.length < sig.required) {
							fullArgs.insert(0, hasThisBinding() ? EThis : ENull);
						}

						var missingCount = missing;
						if (missingCount == 0 && sig != null) {
							final expected = sig.expected;
							if (expected > fullArgs.length)
								missingCount = expected - fullArgs.length;
						}

						// Stage 3 bring-up: upstream often passes `pos` as the last argument to APIs declared
						// as `(required..., ?msg:String, ?pos:haxe.PosInfos)`, relying on Haxe's optional-arg
						// skipping to interpret `f(x, pos)` as `f(x, null, pos)`.
						//
						// Our bootstrap typer/emitter does not model that unification yet. To keep OCaml output
						// type-correct, we insert missing args as `null` immediately *before* a trailing `pos`
						// identifier when we have a signature for the callee.
						if (sig != null && sig.expected > fullArgs.length && fullArgs.length > 0) {
							final last = fullArgs[fullArgs.length - 1];
							final isTrailingPos = switch (last) {
								case EIdent("pos"): true;
								case _: false;
							};
							if (isTrailingPos) {
								final missingBefore = sig.expected - fullArgs.length;
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
						if (c == "getString" && hasThisBinding() && fullArgs.length == 2) {
							fullArgs = [EThis, fullArgs[0], fullArgs[1], ENull];
							missingCount = 0;
						}
						for (_ in 0...missingCount)
							fullArgs.push(ENull);

						final renderedArgs = new Array<String>();
						for (argIndex in 0...fullArgs.length) {
							final renderedArg = "("
								+ exprToOcaml(fullArgs[argIndex], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
									callSigByCallee)
								+ ")";
							renderedArgs.push(renderedArg);
						}
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
				inline function exprToOcamlAsInt64(expr:HxExpr):String {
					final rendered = exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
						callSigByCallee);
					return isInt64Expr(expr) ? rendered : ("Haxe_Int64.ofInt (" + rendered + ")");
				}
				inline function int64DivModField(field:String):String {
					return "(Obj.magic (HxAnon.get (Obj.repr (Haxe_Int64.divMod (" + exprToOcamlAsInt64(a) + ") (" + exprToOcamlAsInt64(b) + "))) "
						+ escapeOcamlString(field) + "))";
				}
				inline function int64BinopCall(binop:String):String {
					final fn = switch (binop) {
						case "+":
							"add";
						case "-":
							"sub";
						case "*":
							"mul";
						case _:
							null;
					}
					return fn == null ? "(Obj.magic 0)" : ("Haxe_Int64." + fn + " (" + exprToOcamlAsInt64(a) + ") (" + exprToOcamlAsInt64(b) + ")");
				}
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
					case "/":
						if (isInt64Expr(a) || isInt64Expr(b)) {
							int64DivModField("quotient");
						} else {
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
						}
					case "+" | "-" | "*" | "%":
						if (isInt64Expr(a) || isInt64Expr(b)) {
							switch (op) {
								case "+" | "-" | "*":
									int64BinopCall(op);
								case "%":
									int64DivModField("modulus");
								case _:
									"(Obj.magic 0)";
							}
						} else {
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
						}
					case "==":
						if (isFloatExpr(a) || isFloatExpr(b)) {
							"((" + exprToOcamlAsFloat(a) + ") = (" + exprToOcamlAsFloat(b) + "))";
						} else {
							"((" + la + ") = (" + rb + "))";
						}
					case "!=":
						if (isFloatExpr(a) || isFloatExpr(b)) {
							"((" + exprToOcamlAsFloat(a) + ") <> (" + exprToOcamlAsFloat(b) + "))";
						} else {
							"((" + la + ") <> (" + rb + "))";
						}
					case "<" | ">" | "<=" | ">=":
						if (isFloatExpr(a) || isFloatExpr(b)) {
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
				final condCode = exprToOcaml(cond, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				// Haxe `Std.parseInt` returns `Null<Int>`. In the OCaml runtime that is an
				// `Obj.t` sentinel-or-boxed-int, so integer fallback branches in ternaries must
				// be boxed too (e.g. `parts.length > 1 ? Std.parseInt(parts[1]) : 0`).
				if (isNullableIntExpr(thenExpr) || isNullableIntExpr(elseExpr)) {"(if ("
					+ condCode
					+ ") then ("
					+ exprToOcamlNullableInt(thenExpr)
					+ ") else ("
					+ exprToOcamlNullableInt(elseExpr)
					+ "))";
				} else {"(if ("
					+ condCode
					+ ") then ("
					+ exprToOcaml(thenExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ") else ("
					+ exprToOcaml(elseExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ "))";
				}
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
								extendTyByIdent(cast tyByIdent, name, TyType.fromHintText("Dynamic"));
							case _:
								extendTyByIdentMany(cast tyByIdent, null, TyType.fromHintText("Dynamic"));
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
				if (isStringExpr(idx)) {if (isMetalProfileActive()) {
					throw "stage3 emitter: metal profile unsupported semantics: string-key indexing is not supported";
				}
					"(Obj.magic (HxAnon.get ("
					+ exprToOcaml(arr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") ("
					+ exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")))";
				} else {final arrCode = exprToOcaml(arr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					final idxCode = exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					// Bind the receiver once before the dynamic array cast. This keeps placeholder
					// receivers like `(Obj.magic 0)` from being re-inferred as `Obj.t` arguments.
					"(let __hx_arr_obj = Obj.repr ("
					+ arrCode
					+ ") in HxBootArray.get ((Obj.obj __hx_arr_obj : _ HxBootArray.t)) ("
					+ idxCode
					+ "))";
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

	static function returnExprToOcaml<TArity, TTy, TStaticImports, TModuleMap, TCallSigs>(expr:HxExpr, allowedValueIdents:Map<String, Bool>,
			?expectedReturnType:TyType, ?arityByIdent:TArity, ?tyByIdent:TTy, ?staticImportByIdent:TStaticImports, ?currentPackagePath:String,
			?moduleNameByPkgAndClass:TModuleMap, ?callSigByCallee:TCallSigs):String {
		final emissionTyByIdent:Map<String, TyType> = new Map();
		final tyByIdentRaw:Null<Map<String, TyType>> = cast tyByIdent;
		final arityByIdentRaw:Null<Map<String, Int>> = cast arityByIdent;
		final staticImportByIdentRaw:Null<Map<String, String>> = cast staticImportByIdent;
		final moduleNameByPkgAndClassRaw:Null<Map<String, String>> = cast moduleNameByPkgAndClass;
		final callSigByCalleeRaw:Null<Map<String, EmitterCallSig>> = cast callSigByCallee;
		final tyKeys:Null<Iterator<String>> = mapKeysRaw(tyByIdentRaw);
		if (tyKeys != null)
			for (name in tyKeys) {
				final ty = mapGetRaw(tyByIdentRaw, name);
				if (ty != null)
					emissionTyByIdent.set(name, ty);
			}
		final allowedKeys:Null<Iterator<String>> = allowedValueIdents == null ? null : allowedValueIdents.keys();
		if (allowedKeys != null)
			for (name in allowedKeys)
				if (allowedValueIdents.get(name) == true && emissionTyByIdent.get(name) == null)
					emissionTyByIdent.set(name, TyType.unknown());
		final emissionTyByIdentRaw = emissionTyByIdent;

		inline function resolveTyIdentName(name:String):String {
			if (mapGetRaw(emissionTyByIdentRaw, name) != null)
				return name;
			final lowered = ocamlValueIdent(name);
			return lowered != name && mapGetRaw(emissionTyByIdentRaw, lowered) != null ? lowered : name;
		}

		inline function hasTyIdent(name:String):Bool {
			return mapGetRaw(emissionTyByIdentRaw, resolveTyIdentName(name)) != null;
		}

		inline function hasThisBinding():Bool {
			return hasTyIdent("this") || hasTyIdent("this_");
		}

		inline function hasStaticImport(name:String):Bool {
			return mapGetRaw(staticImportByIdentRaw, name) != null;
		}

		function tyForIdent(name:String):String {
			final resolved = mapGetRaw(emissionTyByIdentRaw, resolveTyIdentName(name));
			final t:Null<TyType> = cast resolved;
			final ts = t == null ? "" : t.toString();
			final shouldUseLocalHint = resolved == null || ts.length == 0 || ts == "Dynamic" || ts == "Unknown" || ts == "Array";
			if (shouldUseLocalHint) {
				final localHints:Null<Map<String, TyType>> = cast currentFunctionLocalTypeHints;
				if (localHints != null) {
					final hinted:Null<TyType> = cast mapGetRaw(localHints, name);
					if (hinted != null) {
						final hintedS = hinted.toString();
						if (hintedS.length > 0 && hintedS != "Dynamic" && hintedS != "Unknown" && hintedS != "Array")
							return hintedS;
					}
					final lowered = ocamlValueIdent(name);
					if (lowered != name) {
						final loweredHint:Null<TyType> = cast mapGetRaw(localHints, lowered);
						if (loweredHint != null) {
							final loweredHintS = loweredHint.toString();
							if (loweredHintS.length > 0 && loweredHintS != "Dynamic" && loweredHintS != "Unknown" && loweredHintS != "Array")
								return loweredHintS;
						}
					}
				}
			}
			return ts;
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
					} else if (isMutableLocalRefIdent(name)) {
						// Reassigned locals are wrapped as `ref`s during statement lowering. They remain
						// valid bound values even when the best-effort type context misses a later read.
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
						"(Obj.magic (" + exprToOcaml(e, arityByIdentRaw, emissionTyByIdent, staticImportByIdentRaw, currentPackagePath,
							moduleNameByPkgAndClassRaw, callSigByCalleeRaw) + ") : float)";
					case _:
						exprToOcaml(e, arityByIdentRaw, emissionTyByIdent, staticImportByIdentRaw, currentPackagePath, moduleNameByPkgAndClassRaw,
							callSigByCalleeRaw);
				}
			}
			return switch (expr) {
				case EInt(_):
					asFloatValue(expr);
				case EUnop("-", inner):
					"(-.(" + asFloatValue(inner) + "))";
				case _:
					exprToOcaml(expr, arityByIdentRaw, emissionTyByIdent, staticImportByIdentRaw, currentPackagePath, moduleNameByPkgAndClassRaw,
						callSigByCalleeRaw);
			}
		}

		return exprToOcaml(expr, arityByIdentRaw, emissionTyByIdent, staticImportByIdentRaw, currentPackagePath, moduleNameByPkgAndClassRaw,
			callSigByCalleeRaw);
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

	static function stmtListToOcaml(stmts:Array<HxStmt>, allowedValueIdents:Map<String, Bool>, returnExc:String, arityByIdent:Map<String, Int>,
			tyByIdent:Map<String, TyType>, staticImportByIdent:Map<String, String>, currentPackagePath:String, moduleNameByPkgAndClass:Map<String, String>,
			callSigByCallee:Map<String, EmitterCallSig>, localTypeHints:Map<String, TyType>, fnReturnTypes:Map<String, TyType>):String {
		if (stmts == null || stmts.length == 0)
			return "()";

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
		final localHintKeys:Null<Iterator<String>> = localTypeHintsMap == null ? null : localTypeHintsMap.keys();
		if (localHintKeys != null)
			for (k in localHintKeys) {
				final hint = localTypeHintsMap.get(k);
				if (hint != null)
					localHints.set(k, hint);
			}

		inline function isTyNamed(t:Null<TyType>, expected:String):Bool {
			if (t == null)
				return false;
			return t.toString() == expected;
		}

		inline function isInt64HintText(t:String):Bool {
			if (t == null)
				return false;
			final trimmed = StringTools.trim(t);
			if (trimmed.length == 0)
				return false;
			return trimmed == "haxe.Int64"
				|| trimmed == "Int64"
				|| StringTools.endsWith(trimmed, ".Int64")
				|| StringTools.endsWith(trimmed, "_Int64")
				|| trimmed.indexOf("Int64") >= 0;
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

		function hintedTyForIdent(name:String):TyType {
			if (name == null || name.length == 0)
				return TyType.unknown();
			final hinted = localHints.get(name);
			if (hinted != null)
				return hinted;
			var key = name;
			if (mapGetRaw(cast tyByIdent, key) == null) {
				final lowered = ocamlValueIdent(name);
				if (lowered != name && mapGetRaw(cast tyByIdent, lowered) != null)
					key = lowered;
			}
			final resolved = mapGetRaw(cast tyByIdent, key);
			if (resolved == null)
				return TyType.unknown();
			final typed:TyType = cast resolved;
			return typed == null ? TyType.unknown() : typed;
		}

		function inferInitType(e:HxExpr, ?boundName:String, ?boundTy:TyType):TyType {
			if (e == null)
				return TyType.unknown();
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
					if (boundName != null && name == boundName && boundTy != null) boundTy; else hintedTyForIdent(name);
				case ECall(EField(_obj, "substr" | "substring" | "toLowerCase" | "toUpperCase" | "trim"), _args):
					TyType.fromHintText("String");
				case ECall(EField(_obj, "toString"), []):
					TyType.fromHintText("String");
				case ECall(EField(EIdent(owner), field), _args):
					if ((owner == "Int64" || owner == "haxe.Int64")
						&& (field == "make" || field == "ofInt" || field == "parseString" || field == "add" || field == "sub" || field == "mul"
							|| field == "neg" || field == "div" || field == "mod" || field == "divMod")) TyType.fromHintText("haxe.Int64"); else
						TyType.unknown();
				case EBinop(op, left, right):
					final lt = inferInitType(left, boundName, boundTy);
					final rt = inferInitType(right, boundName, boundTy);
					if (op == "+"
						&& (isTyNamed(lt,
							"String") || isTyNamed(rt,
								"String"))) TyType.fromHintText("String"); else if (op == "/"
						&& (isInt64HintText(lt.toString()) || isInt64HintText(rt.toString()))) TyType.fromHintText("haxe.Int64"); else if (op == "/"
						&& ((isTyNamed(lt, "Int") || isTyNamed(lt, "Float"))
							&& (isTyNamed(rt,
								"Int") || isTyNamed(rt,
									"Float")))) TyType.fromHintText("Float"); else if ((op == "+" || op == "-" || op == "*" || op == "%")
						&& (isInt64HintText(lt.toString()) || isInt64HintText(rt.toString()))) TyType.fromHintText("haxe.Int64"); else if ((op == "+"
						|| op == "-" || op == "*" || op == "%")
						&& isTyNamed(lt, "Int")
						&& isTyNamed(rt,
							"Int")) TyType.fromHintText("Int"); else if ((op == "+" || op == "-" || op == "*")
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
				case ECall(EIdent(fn), _args) if (fnReturnTypesMap != null && fnReturnTypesMap.get(fn) != null):
					fnReturnTypesMap.get(fn);
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
						final hinted = hint == null ? TyType.unknown() : TyType.fromHintText(hint);
						final inferred = inferInitType(init);
						final existingNeedsUpgrade = existing == null || existing.isUnknown() || existing.toString() == "Dynamic"
							|| existing.toString() == "Array";
						final explicitHintUseful = !hinted.isUnknown() && hinted.toString() != "Dynamic";
						final inferredUseful = !inferred.isUnknown() && inferred.toString() != "Dynamic";
						if (existingNeedsUpgrade && explicitHintUseful) {
							localHints.set(name, hinted);
						} else if (existingNeedsUpgrade && inferredUseful) {
							localHints.set(name, inferred);
						}
					case _:
				}
			}
		}

		seedLocalHintsFromStmts(stmts);
		final previousStmtLocalTypeHints = currentFunctionLocalTypeHints;
		currentFunctionLocalTypeHints = localHints;

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

		function cloneAllowedValueIdents(source:Map<String, Bool>):Map<String, Bool> {
			final out:Map<String, Bool> = new Map();
			if (source != null)
				for (k in source.keys())
					out.set(k, source.get(k));
			return out;
		}

		function extendTyWithLocals(base:Map<String, TyType>, locals:Map<String, Bool>):Map<String, TyType> {
			final out:Map<String, TyType> = new Map();
			final baseKeys:Null<Iterator<String>> = base == null ? null : base.keys();
			if (baseKeys != null)
				for (k in baseKeys) {
					final existingBase = base.get(k);
					if (existingBase != null)
						out.set(k, existingBase);
				}

			final localNames = new Array<String>();
			final localKeys:Null<Iterator<String>> = locals == null ? null : locals.keys();
			if (localKeys != null)
				for (name in localKeys)
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
					final hintedUseful = !hinted.isUnknown() && hinted.toString() != "Dynamic";
					if (existingBroad && hintedUseful)
						out.set(name, hinted);
				}
			}
			return out;
		}

		function extendTyByIdentLocal(ty:Map<String, TyType>, name:String, t:TyType):Map<String, TyType> {
			final out:Map<String, TyType> = new Map();
			final keys:Null<Iterator<String>> = ty == null ? null : ty.keys();
			if (keys != null)
				for (k in keys) {
					final existing = ty.get(k);
					if (existing != null)
						out.set(k, existing);
				}
			out.set(name, t);
			return out;
		}

		function cloneTyCtxLocal(ty:Map<String, TyType>):Map<String, TyType> {
			final out:Map<String, TyType> = new Map();
			final keys:Null<Iterator<String>> = ty == null ? null : ty.keys();
			if (keys != null)
				for (k in keys) {
					final existing = ty.get(k);
					if (existing != null)
						out.set(k, existing);
				}
			return out;
		}

		function buildStmtTyEntries(tyCtx:Map<String, TyType>):Array<_LocalTyEntry> {
			final out = new Array<_LocalTyEntry>();
			function pushEntry(name:String, ty:Null<TyType>):Void {
				if (name == null || name.length == 0 || ty == null)
					return;
				final tyS = ty.toString();
				if (tyS == null || tyS.length == 0)
					return;
				for (entry in out)
					if (entry.name == name)
						return;
				out.push(new _LocalTyEntry(name, tyS));
			}
			if (tyCtx != null)
				for (name in tyCtx.keys())
					pushEntry(name, tyCtx.get(name));
			for (name in localHints.keys())
				pushEntry(name, localHints.get(name));
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

		function condToOcamlBool(e:HxExpr, tyCtx:Map<String, TyType>):String {
			final erasedReturnTyCtx = cast tyCtx;
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
					boolOrTrue(returnExprToOcaml(e, allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee));
				case EBinop(op, _, _) if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||"):
					boolOrTrue(returnExprToOcaml(e, allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee));
				case _:
					// Conservative default: we do not have real typing for conditions yet.
					// Keep bring-up resilient by treating unknown conditions as true.
					"true";
			};
		}

		function mutableAssignmentStmtToUnit(op:String, name:String, rhs:HxExpr, tyCtx:Null<Map<String, TyType>>):Null<String> {
			if (!isMutableLocalRefIdent(name))
				return null;
			final erasedReturnTyCtx = cast tyCtx;
			inline function localReadIdent(raw:String):String {
				return ocamlReadValueIdent(raw);
			}
			function localTyForIdent(raw:String):String {
				var key = raw;
				if (mapGetRaw(tyCtx, key) == null) {
					final lowered = ocamlValueIdent(raw);
					if (lowered != raw && mapGetRaw(tyCtx, lowered) != null)
						key = lowered;
				}
				final resolved = mapGetRaw(tyCtx, key);
				if (resolved == null) {
					final hinted = localHints.get(raw);
					if (hinted != null)
						return hinted.toString();
					final lowered = ocamlValueIdent(raw);
					if (lowered != raw) {
						final loweredHint = localHints.get(lowered);
						if (loweredHint != null)
							return loweredHint.toString();
					}
					return "";
				}
				final t:TyType = cast resolved;
				return t == null ? "" : t.toString();
			}
			inline function localIntBinopCall(binop:String, left:String, right:String):String {
				return switch (binop) {
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
			function localExprToOcamlAsFloatValue(expr:HxExpr):String {
				return switch (expr) {
					case EInt(v):
						"float_of_int " + Std.string(v);
					case EUnop("-", inner):
						"(-.(" + localExprToOcamlAsFloatValue(inner) + "))";
					case EIdent(raw) if (localTyForIdent(raw) == "Int"):
						"float_of_int " + localReadIdent(raw);
					case EIdent(raw):
						localReadIdent(raw);
					case _:
						exprToOcaml(expr, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				}
			}
			final lhsCode = localReadIdent(name);
			final lhsTy = localTyForIdent(name);
			var rhsRaw = exprToOcaml(rhs, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
			if (rhsRaw == "(Obj.magic 0)")
				switch (rhs) {
					case EIdent(rhsName):
						final lowered = ocamlValueIdent(rhsName);
						final hasTypedLocal = mapGetRaw(tyCtx, rhsName) != null
							|| (lowered != rhsName && mapGetRaw(tyCtx, lowered) != null);
						final hasHintedLocal = localHints.get(rhsName) != null || (lowered != rhsName && localHints.get(lowered) != null);
						final hasAllowedLocal = (allowedValueIdents != null && allowedValueIdents.get(rhsName) == true)
							|| (allowedValueIdents != null && lowered != rhsName && allowedValueIdents.get(lowered) == true);
						if (hasTypedLocal || hasHintedLocal || hasAllowedLocal || isMutableLocalRefIdent(rhsName))
							rhsRaw = localReadIdent(rhsName);
					case _:
				}
			inline function isIntLikeLocalTy(t:String):Bool {
				return t == "Int" || t == "" || t == "Dynamic" || t == "Unknown";
			}
			if (lhsTy == "Float") {
				final rhsFloat = localExprToOcamlAsFloatValue(rhs);
				final directFloatRhs = switch (op) {
					case "+=":
						"((" + lhsCode + ") +. (" + rhsFloat + "))";
					case "-=":
						"((" + lhsCode + ") -. (" + rhsFloat + "))";
					case "*=":
						"((" + lhsCode + ") *. (" + rhsFloat + "))";
					case "/=":
						"((" + lhsCode + ") /. (" + rhsFloat + "))";
					case "%=":
						"(mod_float (" + lhsCode + ") (" + rhsFloat + "))";
					case _:
						null;
				}
				if (directFloatRhs != null)
					return "(let __hx_v = (" + directFloatRhs + ") in (" + ocamlValueIdent(name) + " := __hx_v; ()))";
			}
			if (isIntLikeLocalTy(lhsTy)) {
				final directIntRhs = switch (op) {
					case "+=":
						localIntBinopCall("+", lhsCode, rhsRaw);
					case "-=":
						localIntBinopCall("-", lhsCode, rhsRaw);
					case "*=":
						localIntBinopCall("*", lhsCode, rhsRaw);
					case "%=":
						localIntBinopCall("%", lhsCode, rhsRaw);
					case _:
						null;
				}
				if (directIntRhs != null)
					return "(let __hx_v = (" + directIntRhs + ") in (" + ocamlValueIdent(name) + " := __hx_v; ()))";
			}
			var rhsCode:Null<String> = switch (op) {
				case "=":
					returnExprToOcaml(rhs, allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee);
				case "+=":
					returnExprToOcaml(EBinop("+", EIdent(name), rhs), allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
						currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				case "-=":
					returnExprToOcaml(EBinop("-", EIdent(name), rhs), allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
						currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				case "*=":
					returnExprToOcaml(EBinop("*", EIdent(name), rhs), allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
						currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				case "/=":
					returnExprToOcaml(EBinop("/", EIdent(name), rhs), allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
						currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				case "%=":
					returnExprToOcaml(EBinop("%", EIdent(name), rhs), allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
						currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				case _:
					null;
			}
			if (rhsCode == "(Obj.magic 0)") {
				switch (op) {
					case "+=":
						if (lhsTy == "Int" || lhsTy == "" || lhsTy == "Dynamic" || lhsTy == "Unknown") {
							rhsCode = localIntBinopCall("+", lhsCode, rhsRaw);
						}
					case "-=":
						if (lhsTy == "Int" || lhsTy == "" || lhsTy == "Dynamic" || lhsTy == "Unknown")
							rhsCode = localIntBinopCall("-", lhsCode, rhsRaw);
					case "*=":
						if (lhsTy == "Int" || lhsTy == "" || lhsTy == "Dynamic" || lhsTy == "Unknown")
							rhsCode = localIntBinopCall("*", lhsCode, rhsRaw);
					case "%=":
						if (lhsTy == "Int" || lhsTy == "" || lhsTy == "Dynamic" || lhsTy == "Unknown")
							rhsCode = localIntBinopCall("%", lhsCode, rhsRaw);
					case _:
				}
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

		function stmtToUnit(s:HxStmt, tyCtx:Map<String, TyType>):String {
			final erasedTyCtx = cast tyCtx;
			final erasedReturnTyCtx = cast tyCtx;
			return switch (s) {
				case SBlock(ss, _pos):
					stmtListToOcaml(ss, allowedValueIdents, returnExc, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
						callSigByCallee, localTypeHintsMap, fnReturnTypesMap);
				case SVar(_name, _typeHint, _init, _pos):
					// Handled at the list level because it needs to wrap the remainder with `let ... in`.
					"()";
				case STry(tryBody, _catches, _pos):
					stmtToUnit(tryBody, tyCtx);
				case SThrow(_expr, _pos):
					"()";
				case SSwitch(scrutinee, patterns, bodies, _pos):
					final sw = exprToOcaml(scrutinee, arityByIdent, erasedTyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
						callSigByCallee);
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
							final bodyUnit = stmtToUnit(body, cast caseTy);
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
					final thenUnit = stmtToUnit(thenBranch, tyCtx);
					final elseUnit = elseBranch == null ? "()" : stmtToUnit(elseBranch, tyCtx);
					final condS = condToOcamlBool(cond, erasedTyCtx);
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
					final condS = condToOcamlBool(cond, erasedTyCtx);
					final bodyUnit = stmtToUnit(body, tyCtx);
					if (condS == "false") {
						"()";
					} else {
						"(while " + condS + " do " + bodyUnit + " done)";
					}
				case SDoWhile(body, cond, _pos):
					final bodyUnit = stmtToUnit(body, tyCtx);
					final condS = condToOcamlBool(cond, erasedTyCtx);
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
					final loopAllowed = cloneAllowedValueIdents(allowedValueIdents);
					loopAllowed.set(name, true);
					final bodyUnit = switch (body) {
						case SBlock(ss, _):
							stmtListToOcaml(ss, loopAllowed, returnExc, arityByIdent, bodyTy, staticImportByIdent, currentPackagePath,
								moduleNameByPkgAndClass, callSigByCallee, localTypeHintsMap, fnReturnTypesMap);
						case _:
							stmtToUnit(body, cast bodyTy);
					};
					switch (iterable) {
						case ERange(startExpr, endExpr):
							final start = exprToOcaml(startExpr, arityByIdent, erasedTyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
								callSigByCallee);
							final end = exprToOcaml(endExpr, arityByIdent, erasedTyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass,
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
					"raise ("
					+ returnExc
					+ " (Obj.repr ("
					+ returnExprToOcaml(expr, allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent, currentPackagePath,
						moduleNameByPkgAndClass, callSigByCallee)
					+ ")))";
				case SExpr(expr, _pos):
					// Avoid emitting invalid OCaml for unsupported assignment lvalues while still
					// allowing modeled instance-field assignment side effects.
					switch (expr) {
						case EBinop(op, EIdent(name), rhs):
							final lowered = mutableAssignmentStmtToUnit(op, name, rhs, tyCtx);
							if (lowered != null) {
								lowered;
							} else if (op == "=") {
								"()";
							} else {
								"ignore (" + returnExprToOcaml(expr, allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
									currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")";
							}
						case EBinop("=", EField(_, _), _):
							"ignore (" + returnExprToOcaml(expr, allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
								currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")";
						case EBinop("=", _l, _r):
							"()";
						case _:
							"ignore (" + returnExprToOcaml(expr, allowedValueIdents, null, arityByIdent, erasedReturnTyCtx, staticImportByIdent,
								currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")";
					}
			}
		}

		// Fold right so `var` statements can wrap the rest with `let name = init in ...`.
		//
		// Why
		// - The original implementation repeatedly prepended to the already-rendered tail string.
		// - That is quadratic for large functions; self-emitting `EmitterStage.emitToDir` spends
		//   minutes allocating and collecting those intermediate strings.
		//
		// How
		// - Keep each right-fold wrapper as a prefix/suffix pair.
		// - If a statement definitely returns, reset the base and discard wrappers for unreachable
		//   statements to its right, matching the old lowering.
		// - Materialize the final OCaml string once at the end with `StringBuf`.
		var base = "()";
		final prefixes = new Array<String>();
		final suffixes = new Array<String>();
		inline function wrapStatement(prefix:String, suffix:String):Void {
			prefixes.push(prefix);
			suffixes.push(suffix);
		}
		inline function resetToReturning(rendered:String):Void {
			base = rendered;
			prefixes.resize(0);
			suffixes.resize(0);
		}
		for (i in 0...stmts.length) {
			final idx = stmts.length - 1 - i;
			final s = stmts[idx];
			final tyCtx:Map<String, TyType> = extendTyWithLocals(cast tyByIdent, localsBefore[idx]);
			final prevStmtTyEntries = currentStmtTyEntries;
			currentStmtTyEntries = buildStmtTyEntries(tyCtx);
			_EmitterStageDebug.traceStage3StmtList("begin", currentFunctionName, idx, stmts.length, s);
			switch (s) {
				case SVar(name, _typeHint, init, _pos):
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
								returnExprToOcaml(init, allowedValueIdents, null, arityByIdent, cast tyCtx, staticImportByIdent, currentPackagePath,
									moduleNameByPkgAndClass, callSigByCallee);
						}
					};
					final ident = ocamlValueIdent(name);
					// Keep OCaml warning discipline resilient: Haxe code (especially upstream-ish tests)
					// can contain locals that are intentionally unused. In OCaml, that triggers warnings
					// which can become hard errors under `-warn-error`.
					if (isMutableLocalRefIdent(name)) {
						wrapStatement("let " + ident + " = ref (" + rhs + ") in (ignore " + ident + "; (", "))");
					} else {
						wrapStatement("let " + ident + " = " + rhs + " in (ignore " + ident + "; (", "))");
					}
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
						final rhs = returnExprToOcaml(assign.rhs, allowedValueIdents, null, arityByIdent, cast tyCtx, staticImportByIdent, currentPackagePath,
							moduleNameByPkgAndClass, callSigByCallee);
						wrapStatement("(let " + ident + " = (if " + condToOcamlBool(cond, cast tyCtx) + " then (" + rhs + ") else " + ident
							+ ") in (ignore " + ident + "; (",
							")))");
					} else {
						// Default lowering for if-statements.
						if (stmtAlwaysReturns(s)) {
							resetToReturning(stmtToUnit(s, cast tyCtx));
						} else {
							wrapStatement("(" + stmtToUnit(s, cast tyCtx) + "; ", ")");
						}
					}
				case _:
					// Avoid emitting `...; <nonreturning expr>` sequences, which produce warning 21
					// (nonreturning-statement). This also naturally drops statements that appear after
					// a definite `return` in the same block (unreachable in Haxe).
					if (stmtAlwaysReturns(s)) {
						resetToReturning(stmtToUnit(s, cast tyCtx));
					} else {
						wrapStatement("(" + stmtToUnit(s, cast tyCtx) + "; ", ")");
					}
			}
			currentStmtTyEntries = prevStmtTyEntries;
			_EmitterStageDebug.traceStage3StmtList("done", currentFunctionName, idx, stmts.length, s);
		}
		currentMutableLocalRefNames = prevMutableLocalRefNames;
		currentFunctionLocalTypeHints = previousStmtLocalTypeHints;
		final out = new StringBuf();
		for (i in 0...prefixes.length) {
			final idx = prefixes.length - 1 - i;
			out.add(prefixes[idx]);
		}
		out.add(base);
		for (suffix in suffixes)
			out.add(suffix);
		return out.toString();
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
	static function uniqStrings(xs:Array<String>):Array<String> {
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

	static function ocamldepSort(mlFiles:Array<String>):Array<String> {
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

	static function inferRepoRootForStage3Shims():String {
		final env = Sys.getEnv("HXHX_REPO_ROOT");
		if (env != null && env.length > 0) {
			final candidate = haxe.io.Path.join([env, "packages", "hxhx-core", "shims"]);
			if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate))
				return env;
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
			if (sys.FileSystem.exists(shimsDir) && sys.FileSystem.isDirectory(shimsDir))
				return dir;
			final parent = haxe.io.Path.normalize(haxe.io.Path.join([dir, ".."]));
			if (parent == dir)
				break;
			dir = parent;
		}
		return "";
	}

	static function readStage3ShimTemplate(shimName:String):String {
		final root = inferRepoRootForStage3Shims();
		if (root == null || root.length == 0)
			throw "stage3 emitter: cannot locate repo root for shim templates (set HXHX_REPO_ROOT)";
		final path = haxe.io.Path.join([root, "packages", "hxhx-core", "shims", shimName + ".ml"]);
		if (!sys.FileSystem.exists(path))
			throw "stage3 emitter: missing shim template: " + path;
		return sys.io.File.getContent(path);
	}

	static inline function runtimeModuleNameFromPath(path:String):String {
		final file = haxe.io.Path.withoutDirectory(path);
		final base = StringTools.endsWith(file, ".ml") ? file.substr(0, file.length - 3) : file;
		return upperFirst(base);
	}

	static inline function expectedMainClassFromFile(filePath:Null<String>):Null<String> {
		if (filePath == null || filePath.length == 0)
			return null;
		final name = haxe.io.Path.withoutDirectory(filePath);
		final dot = name.lastIndexOf(".");
		return dot <= 0 ? name : name.substr(0, dot);
	}

	static inline function moduleTypeNameFor(tm:TypedModule):Null<String> {
		// In Haxe, the module name is the file base name (not "the first class we happened to parse").
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

	static inline function baseModuleName(path:String):String {
		final file = haxe.io.Path.withoutDirectory(path);
		return StringTools.endsWith(file, ".ml") ? file.substr(0, file.length - 3) : file;
	}

	public static function emitToDir(p:MacroExpandedProgram, outDir:String, emitFullBodies:Bool = false, buildExecutable:Bool = true,
			ocamlProfile:backend.OcamlProfile = backend.OcamlProfile.Portable):String {
		traceEmitToDirEntry("emitToDir_enter");
		final outAbs = requireEmitToDirOutAbs(outDir);
		installEmitToDirProfile(ocamlProfile);
		ensureEmitToDirOutDir(outAbs);

		// Stage 4 bring-up: emit macro-generated OCaml modules (if any).
		//
		// This is a minimal “generate code” effect: macros can request extra target compilation units
		// without us implementing full typed AST transforms yet.
		final generatedPaths = new Array<String>();
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
		{
			final root = inferRepoRootForStage3Shims();
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

		{
			final shimName = "Lambda";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath,
					"(* hxhx(stage3) bootstrap shim: Lambda *)\n"
					+ "let array it =\n"
					+ "  HxBootArray.of_list (List.of_seq (it : _ Seq.t))\n"
					+ "let list it =\n"
					+ "  List.of_seq (it : _ Seq.t)\n"
					+ "let fold it f first =\n"
					+ "  let acc = ref first in\n"
					+ "  Seq.iter (fun x -> acc := f x !acc) (it : _ Seq.t);\n"
					+ "  !acc\n"
					+ "let has _ _ = false\n"
					+ "let exists _ _ = false\n"
					+ "let iter _ _ = ()\n"
					+ "let count _ = 0\n");
			}
			// Keep bootstrap shims in the compile unit list even on repeat emits into the same out dir.
			generatedPaths.push(shimName + ".ml");
		}
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
				sys.io.File.saveContent(shimPath, readStage3ShimTemplate(shimName));
			}
			generatedPaths.push(shimName + ".ml");
		}
		{
			final shimName = "HxBootProcess";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath, readStage3ShimTemplate(shimName));
			}
			generatedPaths.push(shimName + ".ml");
		}
		{
			// Stage 3 bring-up: stdlib IO helpers lower to `Haxe_io_FPHelper.*`, but ordinary
			// workloads do not always emit the thin wrapper unit even though the runtime helper
			// `runtime/HxFPHelper.ml` is present.
			//
			// Emit the wrapper unconditionally in the program root so workload outputs stay
			// link-closed without depending on placeholder std-unit generation.
			final shimName = "Haxe_io_FPHelper";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			sys.io.File.saveContent(shimPath,
				"(* hxhx(stage3) bootstrap shim: haxe.io.FPHelper *)\n"
				+ "let __reflaxe_ocaml__ = ()\n\n"
				+ "type t = { __hx_type : Obj.t }\n\n"
				+ "let create = fun () -> let self = ({ __hx_type = HxType.class_ \"haxe.io.FPHelper\" } : t) in (\n"
				+ "  ignore ();\n"
				+ "  self\n"
				+ ")\n\n"
				+ "let __empty = fun () -> ({ __hx_type = HxType.class_ \"haxe.io.FPHelper\" } : t)\n\n"
				+ "let i32ToFloat = fun i -> HxFPHelper.i32ToFloat i\n\n"
				+ "let floatToI32 = fun f -> HxFPHelper.floatToI32 f\n\n"
				+ "let i64ToDouble = fun low high -> HxFPHelper.i64ToDouble low high\n\n"
				+
				"let doubleToI64 = fun v -> let parts = Obj.magic (HxFPHelper.doubleToI64Parts v) in let x = Obj.magic (Haxe_Int64.make (HxArray.get (Obj.magic parts) 1) (HxArray.get (Obj.magic parts) 0)) in let tempResult = x in tempResult\n");
			if (generatedPaths.indexOf(shimName + ".ml") == -1)
				generatedPaths.push(shimName + ".ml");
		}
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
		final typedModulesRaw = p.getTypedModules();
		_EmitterStageDebug.traceStage3Phase("after_typed_modules_raw:" + typedModulesRaw.length);
		if (typedModulesRaw.length == 0)
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

		function uniqueTypedModules(mods:Array<TypedModule>):Array<TypedModule> {
			if (mods == null || mods.length <= 1)
				return mods;
			final seen = new Map<String, Bool>();
			final out = new Array<TypedModule>();
			for (tm in mods) {
				if (tm == null)
					continue;
				final filePath = tm.getParsed().getFilePath();
				final moduleTypeName = moduleTypeNameFor(tm);
				final key = (filePath == null ? "" : filePath) + "::" + (moduleTypeName == null ? "" : moduleTypeName);
				if (seen.exists(key))
					continue;
				seen.set(key, true);
				out.push(tm);
			}
			return out;
		}

		final typedModules = uniqueTypedModules(typedModulesRaw);
		_EmitterStageDebug.traceStage3Phase("after_typed_modules_unique:" + typedModules.length);

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
				_EmitterStageDebug.traceStage3Phase("emit_stub_begin:" + moduleName);

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
						out.push("let hex (n : int) (digits : int) : string =");
						out.push("  let hexChars = \"0123456789ABCDEF\" in");
						out.push("  let n32 = Int32.of_int n in");
						out.push("  let rec build (x : Int32.t) (acc : string) : string =");
						out.push("    let digit = Int32.to_int (Int32.logand x 0xFl) in");
						out.push("    let acc2 = (Stdlib.String.make 1 (Stdlib.String.get hexChars digit)) ^ acc in");
						out.push("    let x2 = Int32.shift_right_logical x 4 in");
						out.push("    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2");
						out.push("  in");
						out.push("  let s = build n32 \"\" in");
						out.push("  if digits <= 0 then s else");
						out.push("    let rec pad (s0 : string) : string =");
						out.push("      if Stdlib.String.length s0 < digits then pad (\"0\" ^ s0) else s0");
						out.push("    in");
						out.push("    pad s");
						out.push("");
					}

					// Emit static fields (best-effort).
					final parsedFields = HxClassDecl.getFields(cls);
					final staticTyByIdent:Map<String, TyType> = new Map();
					for (f in parsedFields) {
						if (!HxFieldDecl.getIsStatic(f))
							continue;
						final nameRaw = HxFieldDecl.getName(f);
						if (nameRaw == null || nameRaw.length == 0)
							continue;
						final inferredType = inferStaticFieldType(f, staticTyByIdent);
						final init = HxFieldDecl.getInit(f);
						final initOcaml = init == null ? "(Obj.magic HxRuntime.hx_null)" : exprToOcaml(init, null, staticTyByIdent, null,
							HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, globalCallSigByCallee);
						out.push("let " + ocamlValueIdent(nameRaw) + " = " + initOcaml);
						out.push("");
						final knownType = staticTyByIdent.get(nameRaw);
						if (knownType == null || (knownType.isUnknown() && !inferredType.isUnknown()))
							staticTyByIdent.set(nameRaw, inferredType);
					}
					_EmitterStageDebug.traceStage3Phase("emit_stub_after_fields:" + moduleName);

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
					_EmitterStageDebug.traceStage3Phase("emit_stub_after_functions:" + moduleName);

					final mlPath = haxe.io.Path.join([outAbs, moduleName + ".ml"]);
					_EmitterStageDebug.traceStage3Phase("emit_stub_before_write:" + moduleName);
					sys.io.File.saveContent(mlPath, out.join("\n"));
					_EmitterStageDebug.traceStage3Phase("emit_stub_after_write:" + moduleName);
					_EmitterStageDebug.traceStage3Phase("emit_stub_done:" + moduleName);
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
				final prevLocalCallSigCache = currentLocalCallSigCache;
				final prevInt64 = currentImportInt64;
				final prevInstanceFieldsByTypePath = currentInstanceFieldsByTypePath;
				final prevInstanceMethodsByTypePath = currentInstanceMethodsByTypePath;
				final moduleFilePath = tm.getParsed().getFilePath();
				final mainClassName = HxClassDecl.getName(mainClass);
				currentOcamlModuleName = mainModuleName;
				currentModuleFilePath = moduleFilePath;
				currentLocalCallSigCache = null;
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
					final arityByName:Map<String, Int> = new Map();
					for (tf in typedFns) {
						final parsedFn = parsedByName.get(tf.getName());
						final isStaticFn = parsedFn == null ? true : HxFunctionDecl.getIsStatic(parsedFn);
						final extraThis = isStaticFn ? 0 : 1;
						arityByName.set(tf.getName(), tf.getParams().length + extraThis);
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
							for (p in tf.getParams()) {
								final pn = p.getName();
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
							final args = tf.getParams();
							final ocamlArgs = args.length == 0 ? "()" : args.map(a -> "(" + ocamlValueIdent(a.getName()) + " : "
								+ ocamlTypeFromTy(a.getType()) + ")")
								.join(" ");
							final parsedFn = parsedByName.get(nameRaw);
							final retTy = ocamlTypeFromTy(tf.getReturnType());
							final allowed:Map<String, Bool> = new Map();
							final tyByIdent:Map<String, TyType> = new Map();
							for (a in args)
								allowed.set(a.getName(), true);
							for (a in args)
								tyByIdent.set(a.getName(), a.getType());
							for (name in allowed.keys())
								if (tyByIdent.get(name) == null)
									tyByIdent.set(name, TyType.unknown());
							final body = parsedFn == null ? "(Obj.magic 0)" : returnExprToOcaml(parsedFn.getFirstReturnExpr(), allowed, tf.getReturnType(),
								arityByName, tyByIdent, staticImportByIdent, HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, callSigByCallee);

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
							final name = ocamlValueIdent(nameRaw);
							_EmitterStageDebug.traceStage3Phase("emit_fn_begin:" + mainModuleName + ":" + nameRaw);
							final previousFunctionName = currentFunctionName;
							currentFunctionName = nameRaw;
							final previousFunctionLocalTypeHints = currentFunctionLocalTypeHints;
							final previousRegionKey = currentPortableMetalizationRegionKey;
							currentPortableMetalizationRegionKey = backend.ocaml.PortableMetalizationPlanner.functionRegionKey(moduleFilePath, mainClassName,
								nameRaw);
							if (name == "main")
								sawMain = true;

							final args = tf.getParams();
							final parsedFn = parsedByName.get(nameRaw);
							final isStaticFn = parsedFn == null ? true : HxFunctionDecl.getIsStatic(parsedFn);
							final headArgs = new Array<String>();
							if (!isStaticFn)
								headArgs.push("(this_ : _)");
							for (a in args)
								headArgs.push("(" + ocamlValueIdent(a.getName()) + " : " + ocamlTypeFromTy(a.getType()) + ")");
							final ocamlArgs = headArgs.length == 0 ? "()" : headArgs.join(" ");

							final retTy = ocamlTypeFromTy(tf.getReturnType());
							final allowed:Map<String, Bool> = new Map();
							final tyByIdent:Map<String, TyType> = new Map();
							for (a in args)
								allowed.set(a.getName(), true);
							for (a in args)
								tyByIdent.set(a.getName(), a.getType());
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
							currentFunctionLocalTypeHints = localTypeHints;
							for (localName in localTypeHints.keys()) {
								if (localName == null || localName.length == 0)
									continue;
								final localTy = localTypeHints.get(localName);
								if (localTy == null)
									continue;
								final existing = tyByIdent.get(localName);
								if (existing == null || existing.isUnknown() || existing.toString() == "Dynamic" || existing.toString() == "Array")
									tyByIdent.set(localName, localTy);
							}
							for (name in allowed.keys())
								if (tyByIdent.get(name) == null)
									tyByIdent.set(name, TyType.unknown());

							var body = if (parsedFn == null) {
								"()";
							} else if (!moduleEmitBodies) {
								returnExprToOcaml(parsedFn.getFirstReturnExpr(), allowed, tf.getReturnType(), arityByName, tyByIdent, staticImportByIdent,
									HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, callSigByCallee);
							} else {final exc = "HxReturn_" + escapeOcamlIdentPart(nameRaw);
								exceptions.push("exception " + exc + " of Obj.t");
								final stmts = HxFunctionDecl.getBody(parsedFn);
								"((" //
								+ "try (let _ = "
								+ stmtListToOcaml(stmts, allowed, exc, eraseBoundary(arityByName), tyByIdent, eraseBoundary(staticImportByIdent),
									HxModuleDecl.getPackagePath(decl), eraseBoundary(moduleNameByPkgAndClass), eraseBoundary(callSigByCallee), localTypeHints,
									fnReturnTypesByName)
								+ " in (Obj.magic 0)) "
								+ "with "
								+ exc
								+ " v -> (Obj.magic v)"
								+ ") : "
								+ retTy
								+ ")";
							};
							// Stage3 stdlib bring-up guard:
							// - `haxe.ds.EnumValueMap.compareArg` can recover as
							//   `compare ((Obj.magic 0)) ((Obj.magic 0))`, which misses receiver/arg
							//   forwarding and fails with partial-application type errors.
							// - Normalize that exact degraded body to the receiver-aware local-param call.
							if (mainModuleName == "Haxe_ds_EnumValueMap"
								&& nameRaw == "compareArg"
								&& !isStaticFn
								&& args.length >= 2
								&& body == "compare ((Obj.magic 0)) ((Obj.magic 0))") {
								final arg0 = ocamlReadValueIdent(args[0].getName());
								final arg1 = ocamlReadValueIdent(args[1].getName());
								body = "compare (this_) (" + arg0 + ") (" + arg1 + ")";
							}
							_EmitterStageDebug.traceStage3Phase("emit_fn_after_body:" + mainModuleName + ":" + nameRaw);

							final kw = i == 0 ? "let rec" : "and";
							out.push(kw + " " + name + " " + ocamlArgs + " : " + retTy + " = " + body);
							out.push("");
							_EmitterStageDebug.traceStage3Phase("emit_fn_done:" + mainModuleName + ":" + nameRaw);
							currentFunctionName = previousFunctionName;
							currentFunctionLocalTypeHints = previousFunctionLocalTypeHints;
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
						final initOcaml = init == null ? "(Obj.magic 0)" : exprToOcaml(init, arityByName, staticTyByIdent, staticImportByIdent,
							HxModuleDecl.getPackagePath(decl), moduleNameByPkgAndClass, callSigByCallee);
						out.push("let " + ocamlValueIdent(nameRaw) + " = " + initOcaml);
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
					currentLocalCallSigCache = prevLocalCallSigCache;
					currentImportInt64 = prevInt64;
					currentInstanceFieldsByTypePath = prevInstanceFieldsByTypePath;
					currentInstanceMethodsByTypePath = prevInstanceMethodsByTypePath;
					return mainModuleName + ".ml";
				} catch (e:TyperError) {
					currentOcamlModuleName = prevOcamlModule;
					currentModuleFilePath = prevModuleFilePath;
					currentLocalCallSigCache = prevLocalCallSigCache;
					currentImportInt64 = prevInt64;
					currentInstanceFieldsByTypePath = prevInstanceFieldsByTypePath;
					currentInstanceMethodsByTypePath = prevInstanceMethodsByTypePath;
					throw e;
				} catch (e:String) {
					currentOcamlModuleName = prevOcamlModule;
					currentModuleFilePath = prevModuleFilePath;
					currentLocalCallSigCache = prevLocalCallSigCache;
					currentImportInt64 = prevInt64;
					currentInstanceFieldsByTypePath = prevInstanceFieldsByTypePath;
					currentInstanceMethodsByTypePath = prevInstanceMethodsByTypePath;
					throw e;
				}
			}

			final files = new Array<String>();
			var rootMain:Null<String> = null;
			_EmitterStageDebug.traceStage3Phase("emit_module_begin:" + className);

			// Emit the main class first (typed, optional full bodies).
			final mainPath = isRuntimeProvided ? null : emitMainClass();
			_EmitterStageDebug.traceStage3Phase("emit_module_after_main:" + className);
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
			_EmitterStageDebug.traceStage3Phase("emit_module_done:" + className + ":" + files.length);

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
		_EmitterStageDebug.traceStage3Phase("after_emit_deps:" + emittedModulePaths.length);
		final rr = emitModule(typedModules[0], true);
		for (f in rr.files)
			emittedModulePaths.push(f);
		rootMainPath = rr.rootMain;
		_EmitterStageDebug.traceStage3Phase("after_emit_root:" + emittedModulePaths.length);

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
							+ "let hex (n : int) (digits : int) : string =\n"
							+ "  let hexChars = \"0123456789ABCDEF\" in\n"
							+ "  let n32 = Int32.of_int n in\n"
							+ "  let rec build (x : Int32.t) (acc : string) : string =\n"
							+ "    let digit = Int32.to_int (Int32.logand x 0xFl) in\n"
							+ "    let acc2 = (Stdlib.String.make 1 (Stdlib.String.get hexChars digit)) ^ acc in\n"
							+ "    let x2 = Int32.shift_right_logical x 4 in\n"
							+ "    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2\n"
							+ "  in\n"
							+ "  let s = build n32 \"\" in\n"
							+ "  if digits <= 0 then s else\n"
							+ "    let rec pad (s0 : string) : string =\n"
							+ "      if Stdlib.String.length s0 < digits then pad (\"0\" ^ s0) else s0\n"
							+ "    in\n"
							+ "    pad s\n");
					}
				} else {
					sys.io.File.saveContent(shimPath,
						"(* hxhx(stage3) bootstrap shim: StringTools.hex *)\n"
						+ "\n"
						+ "let hex (n : int) (digits : int) : string =\n"
						+ "  let hexChars = \"0123456789ABCDEF\" in\n"
						+ "  let n32 = Int32.of_int n in\n"
						+ "  let rec build (x : Int32.t) (acc : string) : string =\n"
						+ "    let digit = Int32.to_int (Int32.logand x 0xFl) in\n"
						+ "    let acc2 = (Stdlib.String.make 1 (Stdlib.String.get hexChars digit)) ^ acc in\n"
						+ "    let x2 = Int32.shift_right_logical x 4 in\n"
						+ "    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2\n"
						+ "  in\n"
						+ "  let s = build n32 \"\" in\n"
						+ "  if digits <= 0 then s else\n"
						+ "    let rec pad (s0 : string) : string =\n"
						+ "      if Stdlib.String.length s0 < digits then pad (\"0\" ^ s0) else s0\n"
						+ "    in\n"
						+ "    pad s\n");
					generatedPaths.push(shimFile);
				}
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}
		_EmitterStageDebug.traceStage3Phase("after_shim_stringtools");

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
		_EmitterStageDebug.traceStage3Phase("after_shim_macro_context");
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
		_EmitterStageDebug.traceStage3Phase("after_shim_warning20");

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
		_EmitterStageDebug.traceStage3Phase("after_shim_xml_parser");

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
		_EmitterStageDebug.traceStage3Phase("after_shim_xml");

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
				final patched = StringTools.replace(src, "(-(Php_Const.iNF))", "(-.(Obj.magic Php_Const.iNF : float))");
				if (patched != src)
					sys.io.File.saveContent(shimPath, patched);
			}
		}
		_EmitterStageDebug.traceStage3Phase("after_shim_php_boot");

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
		_EmitterStageDebug.traceStage3Phase("after_shim_callstack");

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
			final shimBody = "(* hxhx(stage3) bootstrap import shim: Type = HxType *)\n"
				+ "include HxType\n"
				+ "\n"
				+ "let getClassName (c : 'a) : string = HxType.getClassName (Obj.repr c)\n"
				+ "let getEnumName (e : 'a) : string = HxType.getEnumName (Obj.repr e)\n"
				+ "let getSuperClass (c : 'a) : Obj.t = HxType.getSuperClass (Obj.repr c)\n"
				+ "let getInstanceFields (c : 'a) : string HxArray.t = HxType.getInstanceFields (Obj.repr c)\n"
				+ "let getClassFields (c : 'a) : string HxArray.t = HxType.getClassFields (Obj.repr c)\n"
				+ "let createInstance (c : 'a) (args : Obj.t HxArray.t) : Obj.t = HxType.createInstance (Obj.repr c) args\n"
				+ "let createEmptyInstance (c : 'a) : Obj.t = HxType.createEmptyInstance (Obj.repr c)\n"
				+ "let createEnum (e : 'a) (ctor_name : string) (params : Obj.t HxArray.t) : Obj.t = HxType.createEnum (Obj.repr e) ctor_name params\n"
				+ "let createEnumIndex (e : 'a) (idx : int) (params : Obj.t HxArray.t) : Obj.t = HxType.createEnumIndex (Obj.repr e) idx params\n"
				+ "let getEnumConstructs (e : 'a) : string HxArray.t = HxType.getEnumConstructs (Obj.repr e)\n";
			sys.io.File.saveContent(shimPath, shimBody);
			if (generatedPaths.indexOf(shimFile) == -1)
				generatedPaths.push(shimFile);
		}
		_EmitterStageDebug.traceStage3Phase("after_shim_type");

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
		_EmitterStageDebug.traceStage3Phase("after_alias_shims:" + generatedPaths.length);

		final exePath = haxe.io.Path.join([outAbs, "out.exe"]);
		try {
			if (sys.FileSystem.exists(exePath))
				sys.FileSystem.deleteFile(exePath);
		} catch (_:haxe.io.Error) {} catch (_:String) {}

		if (!buildExecutable)
			return exePath;

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
		var canonicalCount = 0;
		for (_ in canonicalByLower.keys())
			canonicalCount++;
		_EmitterStageDebug.traceStage3Phase("after_scan_ml_dir:" + canonicalCount);
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
		_EmitterStageDebug.traceStage3Phase("before_ocamldep_sort:" + allMl.length);
		final orderedMl = uniqCaseInsensitive(ocamldepSort(allMl).map(canonicalize));
		_EmitterStageDebug.traceStage3Phase("after_ocamldep_sort:" + orderedMl.length);
		final orderedNoRoot = new Array<String>();
		final rootName = rootMainPath;
		for (f in orderedMl)
			if (rootName == null || f != rootName)
				orderedNoRoot.push(f);
		if (rootName != null)
			orderedNoRoot.push(rootName);
		final orderedNoRootUniq = uniqStrings(orderedNoRoot);
		_EmitterStageDebug.traceStage3Phase("after_ordered_units:" + orderedNoRootUniq.length);

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
		_EmitterStageDebug.traceStage3Phase("before_ocamlopt:" + args.length);
		final code = try {
			Sys.command(ocamlopt, args);
		} catch (e:haxe.io.Error) {
			Sys.setCwd(prevCwd);
			_EmitterStageDebug.traceStage3Phase("ocamlopt_io_error");
			throw e;
		} catch (e:String) {
			Sys.setCwd(prevCwd);
			_EmitterStageDebug.traceStage3Phase("ocamlopt_string_error");
			throw e;
		};
		Sys.setCwd(prevCwd);
		_EmitterStageDebug.traceStage3Phase("after_ocamlopt:" + code);
		if (code != 0)
			throw "stage3 emitter: ocamlopt failed with exit code " + code;
		_EmitterStageDebug.traceStage3Phase("before_missing_exe_check");
		if (!sys.FileSystem.exists(exePath))
			throw "stage3 emitter: missing built executable: " + exePath;
		_EmitterStageDebug.traceStage3Phase("after_missing_exe_check");
		return exePath;
	}
}
