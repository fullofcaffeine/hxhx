package hxhx;

import haxe.io.Path;
import hxhx.runtime.NullableRuntimeString;
import haxe.io.Eof;
import hxhx.Stage1Compiler.Stage1Args;
#if !hxhx_stage0_no_external_macro_host
import hxhx.macro.MacroHostClient;
#end
import hxhx.macro.MacroRuntimeMode;
import hxhx.macro.MacroRuntimeSession;
import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.BackendRegistry;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.GenIrProgram;
import backend.IBackend;
import backend.OcamlProfile;

private typedef HaxelibSpec = LibraryResolver.LibrarySpec;

/**
	Stage 3 native compiler lane (`--hxhx-stage3`).

	Last audited: 2026-03-03.

	Why
	- Stage 1 proves we can parse and resolve modules without delegating to Stage0 `haxe`,
	  but it intentionally stops at `--no-output`.
	- Stage 3 is the first rung where `hxhx` behaves like a *real compiler*:
	  parse → resolve → type → emit target code → build an executable.
	- This lane is the native orchestration entrypoint for builtin backends and
	  plugin-backed backend dispatch during Stage3 workflows.

	What (today)
	- Supports the Stage3 CLI surface:
	  - `-cp <dir>` / `-p <dir>` (repeatable)
	  - `-main <Dotted.TypeName>`
	  - `-C / --cwd` (affects relative `-cp` and `--hxhx-out`)
	  - `.hxml` expansion (via `Stage1Args`)
	  - Stage3 control flags (`--hxhx-backend`, `--hxhx-no-emit`, `--hxhx-no-run`, etc.)
	- Adds one Stage3 output flag:
	  - `--hxhx-out <dir>`: where emitted `.ml` and the built executable are written
	- Runs the Stage 2/3 pipeline from `packages/hxhx-core`:
	  - `ResolverStage.parseProject` (transitive import closure)
	  - `TyperStage.typeModule` (native typing lane)
	  - backend selection + dispatch (`BackendRegistry`, provider/manifest resolution)
	  - `EmitterStage.emitToDir` when using the bootstrap OCaml emitter lane

	Runtime integration boundary
	- Stage3 orchestration does not own portable/metal runtime-plan reporting.
	- Reflaxe runtime planning/report artifacts are generated in the backend/runtime
	  pipeline (`RuntimeCopier`/`OcamlCompiler`), while Stage3 bootstrap OCaml output
	  owns only the local emit/copy/link behavior in `EmitterStage.emitToDir`.

	Non-goals
	- Full macro integration (`@:build`, typed AST transforms, etc.) is Stage 4.
	- Full Haxe typing is beyond this bring-up rung.

	Gotchas
	- This is an internal bootstrap flag: it must never be forwarded to stage0 `haxe`.
	- Backend availability depends on the selected lane (builtin registry and/or
	  plugin manifest/provider inputs).
**/
class Stage3Compiler {
	static function error(msg:String):Int {
		Sys.println("hxhx(stage3): " + msg);
		return 2;
	}

	static function haxeDiagnosticError(msg:String):Int {
		Sys.stderr().writeString(msg + "\n");
		Sys.stderr().flush();
		return 1;
	}

	static function hasFlag(args:Array<String>, flag:String):Bool {
		return Stage3Args.hasFlag(args, flag);
	}

	static function parseGlobalStage3Flags(args:Array<String>) {
		return Stage3Args.parseGlobalStage3Flags(args);
	}

	static inline function hasConfiguredExternalMacroHostExe():Bool {
		#if hxhx_stage0_no_external_macro_host
		return false;
		#else
		return MacroHostClient.resolveMacroHostExePath().length > 0;
		#end
	}

	/**
		Resolve a Stage3 builtin backend implementation by ID.

		Why
		- `hxhx --ocaml` and native `--js <file>` routes builtin targets through one Stage3 execution path.
		- We need an explicit mapping from target IDs to backend implementations.

		What
		- Supports:
		  - `ocaml-stage3` (existing linked OCaml backend)
		  - `js-native` (MVP non-delegating JS backend)

		How
		- Fail fast on unknown IDs so callers never silently delegate or run the wrong backend.
	**/
	static function resolveBuiltinBackend(backendId:String):IBackend {
		return BackendRegistry.requireForTarget(backendId);
	}

	/**
		Extract `--wait <mode>` from raw Stage3 args.

		Why
		- Upstream display clients (`haxeserver`) launch a long-lived compiler process
		  with `--wait stdio` and send framed requests over stdin.
		- Stage3 must peel this flag *before* `.hxml` expansion so it can switch from
		  "single compile invocation" mode into "request server" mode.

		What
		- Returns one optional wait mode plus all remaining args.
		- Multiple `--wait` flags are rejected as invalid.
	**/
	static function parseWaitMode(args:Array<String>) {
		return Stage3WaitServer.parseWaitMode(args);
	}

	/**
		Extract `--connect <mode>` from raw Stage3 args.

		Why
		- Upstream compiler-server clients can issue one-shot requests with `--connect`.
		- Stage3 needs a non-delegating path for that request flow, especially for display-style
		  requests that are issued against a long-lived `--wait <host:port>` server.

		What
		- Returns one optional connect mode plus all remaining args.
		- Multiple `--connect` flags are rejected as invalid.
	**/
	static function parseConnectMode(args:Array<String>) {
		return Stage3WaitServer.parseConnectMode(args);
	}

	static function targetDefineForBackend(backendId:String):String {
		return Stage3Args.targetDefineForBackend(backendId);
	}

	static function findTargetOutputFileHint(args:Array<String>, backendId:String):Null<String> {
		return Stage3Args.findTargetOutputFileHint(args, backendId);
	}

	static function findTargetOutputDirectoryHint(args:Array<String>, backendId:String):Null<String> {
		return Stage3Args.findTargetOutputDirectoryHint(args, backendId);
	}

	static function canRunNode():Bool {
		return Stage3RunSupport.canRunNode();
	}

	static function runSafeCommandOnlyHooks(commands:Array<String>, cwd:String):Null<Int> {
		return Stage3RunSupport.runSafeCommandOnlyHooks(commands, cwd);
	}

	static function runSafeJavaJarHookForArtifact(commands:Array<String>, cwd:String, artifactPath:String):Null<Int> {
		return Stage3RunSupport.runSafeJavaJarHookForArtifact(commands, cwd, artifactPath);
	}

	static function runSafePythonHookForArtifact(commands:Array<String>, cwd:String, artifactPath:String):Null<Int> {
		return Stage3RunSupport.runSafePythonHookForArtifact(commands, cwd, artifactPath);
	}

	static function runWaitStdio(baseArgs:Array<String>):Int {
		return Stage3WaitServer.runWaitStdio(baseArgs, runOne, error);
	}

	/**
		Run Stage3 as a persistent `--wait <host:port>` socket server.

		Implementation note
		- This path uses a small OCaml runtime bridge (`HxHxCompilerServer`) because the current
		  bootstrap codegen does not yet support `sys.net.Socket` property access (`input`/`output`)
		  from Stage3 Haxe code.
		- The bridge currently focuses on display-style compiler-server requests.
	**/
	static function runWaitSocket(mode:String, _baseArgs:Array<String>):Int {
		return Stage3WaitServer.runWaitSocket(mode, error);
	}

	/**
		Execute a one-shot Stage3 `--connect <host:port>` request.

		Implementation note
		- The socket transport itself is handled by `HxHxCompilerServer.connect`.
		- Stage3 prepares the request payload and preserves existing response formatting behavior.
	**/
	static function runConnect(connectMode:String, requestArgs:Array<String>):Int {
		return Stage3WaitServer.runConnect(connectMode, requestArgs, error);
	}

	static function escapeOneLine(s:String):String {
		return Stage3DiagnosticsSupport.escapeOneLine(s);
	}

	static function countUnsupportedExprsInExpr(e:Null<HxExpr>):Int {
		return Stage3DiagnosticsSupport.countUnsupportedExprsInExpr(e);
	}

	static function bool01(v:Bool):String
		return v ? "1" : "0";

	static function isTrueEnv(name:String):Bool {
		final v = trim(Sys.getEnv(name));
		return v == "1" || v == "true" || v == "yes";
	}

	static function formatException(e:TyperError):String {
		return Stage3DiagnosticsSupport.formatException(e);
	}

	static function rawTyperDiagnostic(e:TyperError):Null<String> {
		return Stage3DiagnosticsSupport.rawTyperDiagnostic(e);
	}

	static function formatDynamicException(e:Dynamic):String {
		return Stage3DiagnosticsSupport.formatDynamicException(e);
	}

	static function collectUnsupportedExprRawInModule(pm:ParsedModule, max:Int):Array<String> {
		return Stage3DiagnosticsSupport.collectUnsupportedExprRawInModule(pm, max);
	}

	static function countUnsupportedExprsInModule(pm:ParsedModule):Int {
		return Stage3DiagnosticsSupport.countUnsupportedExprsInModule(pm);
	}

	static function countUnsupportedExprsInFunction(fn:HxFunctionDecl):Int {
		return Stage3DiagnosticsSupport.countUnsupportedExprsInFunction(fn);
	}

	static function resolveHaxelibSpec(lib:String, cwd:String, seen:Map<String, Bool>, depth:Int):HaxelibSpec {
		return LibraryResolver.resolve(lib, cwd, seen, depth);
	}

	static function absFromCwd(cwd:String, path:String):String {
		return Stage3PathSupport.absFromCwd(cwd, path);
	}

	/**
		Infer a module/type root from a `--display <path@mode>` request.

		Why
		- Upstream display server calls often omit `-main` and rely on `--display <file@...>`.
		- Stage3 previously treated those invocations as "missing -main", which blocked display
		  fixture execution under non-delegating `hxhx` paths.

		How
		- Parse the file part before `@`.
		- Resolve it against classpaths to derive a dotted module path (`src/a/b/Main.hx` -> `a.b.Main`).
		- Fallback to file basename when classpath matching is not possible.
	**/
	#if !hxhx_stage0_no_display
	static function inferMainFromDisplayRequest(displayRequest:String, classPaths:Array<String>, cwd:String):String {
		return Stage3PathSupport.inferMainFromDisplayRequest(displayRequest, classPaths, cwd);
	}
	#end

	static function inferRepoRootForScripts():String {
		return Stage3PathSupport.inferRepoRootForScripts();
	}

	static function trim(s:String):String {
		return NullableRuntimeString.trimToEmpty(s);
	}

	static function parseDelimitedList(raw:String):Array<String> {
		return Stage3MacroHostSupport.parseDelimitedList(raw);
	}

	static function loadDynamicBackendProviders(rawDefines:Array<String>):Void {
		Stage3BackendPluginSupport.loadDynamicBackendProviders(rawDefines);
	}

	static function isBuiltinMacroExpr(expr:String):Bool {
		return Stage3MacroHostSupport.isBuiltinMacroExpr(expr);
	}

	static function anyNonBuiltinMacro(exprs:Array<String>):Bool {
		return Stage3MacroHostSupport.anyNonBuiltinMacro(exprs);
	}

	static function shouldAutoBuildMacroHost():Bool {
		return Stage3MacroHostSupport.shouldAutoBuildMacroHost();
	}

	static function buildMacroHostExe(repoRoot:String, extraCp:Array<String>, entrypoints:Array<String>):String {
		return Stage3MacroHostSupport.buildMacroHostExe(repoRoot, extraCp, entrypoints);
	}

	static function parseGeneratedMembers(members:Array<String>):{functions:Array<HxFunctionDecl>, fields:Array<HxFieldDecl>} {
		return Stage3BuildMacroSupport.parseGeneratedMembers(members);
	}

	static function buildFieldsPayloadForParsed(pm:ParsedModule):String {
		return Stage3BuildMacroSupport.buildFieldsPayloadForParsed(pm);
	}

	static function collectBuildMacroExprs(source:String, modulePath:String):Array<String> {
		return Stage3BuildMacroSupport.collectBuildMacroExprs(source, modulePath);
	}

	static function dispatchOnTypeNotFoundHooks(macroSession:Null<MacroRuntimeSession>, typePath:String):Bool {
		return Stage3BuildMacroSupport.dispatchOnTypeNotFoundHooks(macroSession, typePath);
	}

	static function runOne(args:Array<String>):Int {
		// Extract stage3-only flags before passing the remainder to `Stage1Args`.
		final g = try {
			parseGlobalStage3Flags(args);
		} catch (e:String) {
			return error(e);
		}
		final outDir = g.outDir;
		final backendId = g.backendId;
		final macroRuntimeMode = try {
			MacroRuntimeMode.resolve(g.macroRuntimeMode);
		} catch (e:String) {
			return error(e);
		}
		var typeOnly = g.typeOnly;
		var emitFullBodies = g.emitFullBodies;
		var noEmit = g.noEmit;
		var noRun = g.noRun;
		final rest = g.rest;
		MacroRuntimeMode.emitMarker(macroRuntimeMode);
		final targetOutputHintRaw = findTargetOutputFileHint(rest, backendId);
		final targetOutputDirHintRaw = findTargetOutputDirectoryHint(rest, backendId);

		// Stage3 bring-up is intentionally stricter than a full `haxe` CLI, but it needs to be able to
		// *attempt* upstream-ish hxmls (e.g. Gate1 `compile-macro.hxml`) without failing immediately on
		// non-essential flags. We therefore use Stage1Args in a small permissive mode that ignores
		// a curated set of known upstream flags (e.g. `--interp`, `--debug`, `--dce`, `--resource`).
		final parsed = Stage1Args.parse(rest, true);
		if (parsed == null)
			return 2;
		final parsedDefines = Stage1Args.getDefines(parsed);
		final parsedNoOutput = Stage1Args.getNoOutput(parsed);
		final parsedMain = Stage1Args.getMain(parsed);
		final parsedRoots = Stage1Args.getRoots(parsed);
		final parsedMacros = Stage1Args.getMacros(parsed);
		final parsedCwd = Stage1Args.getCwd(parsed);
		final parsedClassPaths = Stage1Args.getClassPaths(parsed);
		final parsedLibs = Stage1Args.getLibs(parsed);
		final parsedHadCmd = Stage1Args.getHadCmd(parsed);
		final parsedCmdCommands = Stage1Args.getCmdCommands(parsed);
		// Upstream often uses `--interp` as “compile + run now”. In Stage3 (native OCaml),
		// we emulate this by enabling the full-body emission rung.
		final sawInterp = parsedDefines != null && parsedDefines.indexOf("interp=1") != -1;
		emitFullBodies = emitFullBodies || sawInterp;
		if (backendId == "js-native") {
			emitFullBodies = true;
		}

		// Respect upstream `--no-output` by treating it as “no emit” in bring-up.
		//
		// Override rule
		// - If the caller explicitly provides `--hxhx-out <dir>`, treat that as an explicit request
		//   to emit/build even if the `.hxml` contains `--no-output` (some Stage3 examples share
		//   `.hxml` files with stage0 paths where `--no-output` is desirable).
		if (outDir.length == 0)
			noEmit = noEmit || parsedNoOutput;

		function inferMainFromMacroExpr(expr:String):String {
			return Stage3PathSupport.inferMainFromMacroExpr(expr);
		}

		// Upstream allows invocations without `-main`:
		// - "macro-only" compilation (`--macro ...`) and/or
		// - compile-time suites that pass "dot paths" as positional args (type/module roots).
		//
		// Stage3 bring-up supports this by deriving resolver roots in this priority order:
		// 1) explicit `-main`
		// 2) positional roots (`<pack.TypeName>` args)
		// 3) first `--macro` entrypoint's type path (before the final `.method(...)`)
		final roots0 = new Array<String>();
		final displayRequest = Stage1Args.getDisplayRequest(parsed);
		if (parsedMain != null && parsedMain.length > 0) {
			roots0.push(parsedMain);
		} else if (parsedRoots != null && parsedRoots.length > 0) {
			for (r in parsedRoots)
				if (r != null && r.length > 0)
					roots0.push(r);
		} else if (parsedMacros.length > 0) {
			final inferred = inferMainFromMacroExpr(parsedMacros[0]);
			if (inferred.length == 0)
				return error("missing -main <TypeName>");
			roots0.push(inferred);
		}

		// Type-only mode is intended to answer “how far does the typer get?” without requiring a
		// working macro host. Upstream-ish workloads (e.g. `tests/unit/compile-macro.hxml`) often
		// include `--macro` directives which are essential for *real* compilation, but are not
		// necessary to diagnose missing parser/typer coverage.
		//
		// We therefore skip macros entirely when `--hxhx-type-only` is enabled.
		//
		// Note: This is a bring-up behavior. The Gate1 “non-delegating” acceptance run will
		// require real macro execution; type-only is only for diagnostics.
		if (typeOnly && parsedMacros.length > 0) {
			for (i in 0...parsedMacros.length) {
				Sys.println("macro_skipped[" + i + "]=" + parsedMacros[i]);
			}
		}

		// Stage4 bring-up: expression macro allowlist.
		//
		// These are call sites in *normal code* (not CLI `--macro`) that we will attempt to expand
		// before typing by asking the macro host for a replacement expression snippet.
		final exprMacros = Stage3MacroHostSupport.exprMacroAllowlistFromEnv();

		var macroSession:Null<MacroRuntimeSession> = null;
		inline function closeMacroSession():Void {
			if (macroSession != null) {
				macroSession.close();
				macroSession = null;
			}
		}

		final hostCwd = try Sys.getCwd() catch (_:String) ".";
		final cwd = absFromCwd(hostCwd, parsedCwd);
		if (!sys.FileSystem.exists(cwd) || !sys.FileSystem.isDirectory(cwd)) {
			return error("cwd is not a directory: " + cwd);
		}

		if (roots0.length == 0 && displayRequest != null && displayRequest.length > 0) {
			#if hxhx_stage0_no_display
			return error("display requests unavailable in stage0 no-display profiling lane");
			#else
			final inferred = inferMainFromDisplayRequest(displayRequest, parsedClassPaths, cwd);
			if (inferred.length > 0)
				roots0.push(inferred);
			#end
		}

		if (roots0.length == 0) {
			// Some upstream `.hxml` units are "command only" (e.g. Flash's `-cmd compc ...`) and do
			// not invoke the Haxe compiler in a way that produces a `-main`.
			//
			// For Stage3 bring-up we do not execute `-cmd`/`--cmd`; treat these units as skipped so
			// diagnostic runners can still traverse the rest of the multi-unit file.
			if (parsedHadCmd) {
				final cmdCode = runSafeCommandOnlyHooks(parsedCmdCommands, cwd);
				if (cmdCode != null) {
					if (cmdCode != 0)
						return error("command hook failed with exit code " + Std.string(cmdCode));
					Sys.println("stage3=cmd_ok");
					return 0;
				} else {
					Sys.println("stage3=skipped_cmd_only");
					return 0;
				}
			}
			return error("missing -main <TypeName>");
		}

		final outAbs = absFromCwd(cwd, (outDir.length > 0 ? outDir : "out_stage3"));

		// Macro state exists even in non-macro runs; it is a no-op unless the macro host calls back.
		hxhx.macro.MacroState.reset();
		final libsResolved = {
			final seen = new Map<String, Bool>();
			final out = new Array<HaxelibSpec>();
			for (lib in parsedLibs)
				out.push(resolveHaxelibSpec(lib, cwd, seen, 0));
			out;
		}
		final libDefines = {
			final out = new Array<String>();
			for (s in libsResolved)
				for (d in s.defines)
					if (out.indexOf(d) == -1)
						out.push(d);
			out;
		}
		final allDefines = parsedDefines.concat(libDefines);
		hxhx.macro.MacroState.seedFromCliDefines(allDefines);
		final macroStdPaths = {
			final out = new Array<String>();
			final envStd = trim(Sys.getEnv("HAXE_STD_PATH"));
			if (envStd.length > 0)
				out.push(Path.normalize(envStd));
			final inferredStd = Stage1Args.inferStdRootForCwd(cwd);
			if (inferredStd.length > 0) {
				final normalized = Path.normalize(inferredStd);
				var seen = false;
				for (cp in out) {
					if (Path.normalize(cp) == normalized) {
						seen = true;
						break;
					}
				}
				if (!seen)
					out.push(inferredStd);
			}
			out;
		}
		final backendTargetDefine = targetDefineForBackend(backendId);
		hxhx.macro.MacroState.seedCompilerConfiguration(args, macroStdPaths, backendTargetDefine);
		hxhx.macro.MacroState.setGeneratedHxDir(haxe.io.Path.join([outAbs, "_gen_hx"]));

		final libMacros = {
			final out = new Array<String>();
			for (s in libsResolved)
				for (m in s.macros)
					if (out.indexOf(m) == -1)
						out.push(m);
			out;
		}
		final runHaxelibMacros = isTrueEnv("HXHX_RUN_HAXELIB_MACROS");

		final macroHostClassPaths = {
			final base = parsedClassPaths.map(cp -> absFromCwd(cwd, cp));
			final libs = new Array<String>();
			for (s in libsResolved)
				for (p in s.classPaths)
					libs.push(absFromCwd(cwd, p));
			final outAll = base.concat(libs);

			// Avoid passing an explicit std classpath to the macro host build.
			//
			// Why
			// - The macro host is compiled with stage0 `haxe`, which already has its own std.
			// - Adding `HAXE_STD_PATH` to the classpath can change resolution order and shadow our
			//   macro-host overrides (e.g. `haxe.macro.Context`), causing compile failures.
			final stdCp = trim(Sys.getEnv("HAXE_STD_PATH"));
			if (stdCp.length > 0) {
				final stdAbs = Path.normalize(stdCp);
				final filtered = new Array<String>();
				for (cp in outAll) {
					if (Path.normalize(cp) != stdAbs)
						filtered.push(cp);
				}
				filtered;
			} else {
				outAll;
			}
		}

		if (!typeOnly && (parsedMacros.length > 0 || exprMacros.length > 0 || (runHaxelibMacros && libMacros.length > 0))) {
			// Stage3 dev/CI convenience: auto-build a macro host that includes the classpaths needed
			// for:
			// - requested CLI `--macro` entrypoints, and
			// - expression macro allowlist entrypoints (HXHX_EXPR_MACROS).
			//
			// This is only enabled when `HXHX_MACRO_HOST_AUTO_BUILD=1` (or true/yes) is set.
			//
			// Notes
			// - This is a bring-up tool. It is not meant to be used for production builds.
			// - The produced macro host is built via stage0 `haxe` (the script), not via hxhx itself.
			if (macroRuntimeMode == MacroRuntimeMode.EXTERNAL_HOST && !hasConfiguredExternalMacroHostExe() && shouldAutoBuildMacroHost()) {
				final repoRoot = inferRepoRootForScripts();
				if (repoRoot.length == 0)
					return error("macro host auto-build enabled, but repo root could not be inferred (set HXHX_REPO_ROOT)");

				try {
					final entrypoints = new Array<String>();
					// Library-provided macros (from `haxelib path <lib>` output) when enabled.
					if (runHaxelibMacros) {
						for (e in libMacros)
							if (!isBuiltinMacroExpr(e) && entrypoints.indexOf(e) == -1)
								entrypoints.push(e);
					}
					// CLI macros: include only non-builtin expressions (builtins are already compiled into the host).
					if (anyNonBuiltinMacro(parsedMacros)) {
						for (e in parsedMacros)
							if (!isBuiltinMacroExpr(e) && entrypoints.indexOf(e) == -1)
								entrypoints.push(e);
					}
					// Expression macros: always include (they are not builtins by default).
					for (e in exprMacros)
						if (entrypoints.indexOf(e) == -1)
							entrypoints.push(e);
					final exe = buildMacroHostExe(repoRoot, macroHostClassPaths, entrypoints);
					Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);
				} catch (e:String) {
					return error("macro host auto-build failed: " + e);
				}
			}

			// Stage 4 bring-up slice: support CLI `--macro` by routing expressions to the macro host.
			//
			// This does not yet allow macros to transform the typed AST (e.g. `@:build`). It is purely
			// “execute macro expressions and surface deterministic results/errors”.
			try {
				macroSession = MacroRuntimeMode.openSession(macroRuntimeMode);
				if (runHaxelibMacros) {
					for (i in 0...libMacros.length)
						Sys.println("lib_macro_run[" + i + "]=" + macroSession.run(libMacros[i]));
				}
				for (i in 0...parsedMacros.length)
					Sys.println("macro_run[" + i + "]=" + macroSession.run(parsedMacros[i]));
			} catch (e:String) {
				closeMacroSession();
				return error("macro failed: " + e);
			}

			// Bring-up diagnostics: dump HXHX_* defines set by macros so tests can assert macro effects.
			for (name in hxhx.macro.MacroState.listDefineNames()) {
				if (StringTools.startsWith(name, "HXHX_")) {
					Sys.println("macro_define[" + name + "]=" + hxhx.macro.MacroState.definedValue(name));
				}
			}
		}

		final classPaths = {
			final base = parsedClassPaths.map(cp -> absFromCwd(cwd, cp));
			final libs = new Array<String>();
			for (s in libsResolved)
				for (p in s.classPaths)
					libs.push(absFromCwd(cwd, p));
			final extra = hxhx.macro.MacroState.listClassPaths().map(cp -> absFromCwd(cwd, cp));
			final out = base.concat(libs).concat(extra);
			final generatedHxDir = hxhx.macro.MacroState.getGeneratedHxDir();
			if (generatedHxDir != null && generatedHxDir.length > 0) {
				final generatedNorm = Path.normalize(generatedHxDir);
				var hasGeneratedDir = false;
				for (cp in out) {
					if (Path.normalize(cp) == generatedNorm) {
						hasGeneratedDir = true;
						break;
					}
				}
				if (!hasGeneratedDir)
					out.push(generatedHxDir);
			}
			// Defensive fallback: ensure std root is present even when Stage1 parse paths are
			// provided in permissive mode via target presets and env std vars are unset.
			final inferredStd = Stage1Args.inferStdRootForCwd(cwd);
			if (inferredStd.length > 0) {
				final inferredNorm = Path.normalize(inferredStd);
				var hasStd = false;
				for (cp in out) {
					if (Path.normalize(cp) == inferredNorm) {
						hasStd = true;
						break;
					}
				}
				if (!hasStd)
					out.push(inferredStd);
			}
			ResolverStage.withImplicitCwdClassPath(out, cwd);
		}

		// Defines available for conditional compilation filtering.
		//
		// Notes
		// - CLI `-D` defines were seeded into MacroState at the start of the run.
		// - Macro-time `Compiler.define(...)` calls (reverse RPC) also populate MacroState.
		// - ResolverStage will use this map to strip inactive `#if` branches before parsing.
		final definesMap = HxDefineMap.fromRawDefines(allDefines);
		definesMap.set("sys", "1");
		definesMap.set(backendTargetDefine, "1");
		for (n in hxhx.macro.MacroState.listDefineNames()) {
			definesMap.set(n, hxhx.macro.MacroState.definedValue(n));
		}
		if (backendId == "ocaml-stage3") {
			try {
				final profile = OcamlProfile.fromDefineValue(definesMap.get("ocaml_profile"));
				definesMap.set("ocaml_profile", OcamlProfile.toDefineValue(profile));
			} catch (e:String) {
				closeMacroSession();
				return error(e);
			}
		}

		final roots = roots0.concat(hxhx.macro.MacroState.listIncludedModules());
		final resolved = try {
			if (noEmit && !typeOnly)
				ResolverStage.parseProjectRootsShallow(classPaths, roots, definesMap)
			else
				ResolverStage.parseProjectRoots(classPaths, roots, definesMap);
		} catch (e:TyperError) {
			closeMacroSession();
			return error("resolve failed: " + formatException(e));
		} catch (e:String) {
			closeMacroSession();
			return error("resolve failed: " + e);
		}
		if (resolved.length == 0)
			return error("resolver returned an empty module graph");
		Sys.println("resolved_modules=" + resolved.length);
		if (backendId == "java-native") {
			final overloadDiagnostic = JavaNoEmitDiagnostics.overloadCollisionDiagnosticForResolved(resolved);
			if (overloadDiagnostic != null) {
				closeMacroSession();
				return haxeDiagnosticError(overloadDiagnostic);
			}
		}

		// Stage4 bring-up: apply `@:build(...)` macros by asking the macro host to emit raw
		// member snippets (reverse RPC) that we merge into the parsed module surface before typing.
		//
		// This is a small rung that does *not* implement upstream macro semantics yet.
		var anyBuildMacros = false;
		final buildExprsAll = new Array<String>();
		for (m in resolved) {
			final pm = ResolvedModule.getParsed(m);
			final exprs = collectBuildMacroExprs(pm.getSource(), ResolvedModule.getModulePath(m));
			if (exprs.length > 0) {
				anyBuildMacros = true;
				for (e in exprs)
					buildExprsAll.push(e);
			}
		}

		var resolvedForTyping = resolved;
		if (!typeOnly && anyBuildMacros) {
			// Ensure we have a macro host session.
			if (macroSession == null) {
				// Optional convenience: auto-build a macro host that contains the build macro entrypoints.
				if (macroRuntimeMode == MacroRuntimeMode.EXTERNAL_HOST
					&& !hasConfiguredExternalMacroHostExe()
					&& shouldAutoBuildMacroHost()) {
					final repoRoot = inferRepoRootForScripts();
					if (repoRoot.length == 0)
						return error("macro host auto-build enabled, but repo root could not be inferred (set HXHX_REPO_ROOT)");
					try {
						final entrypoints = new Array<String>();
						for (e in buildExprsAll)
							if (!isBuiltinMacroExpr(e) && entrypoints.indexOf(e) == -1)
								entrypoints.push(e);
						final exe = buildMacroHostExe(repoRoot, macroHostClassPaths, entrypoints);
						Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);
					} catch (e:String) {
						return error("macro host auto-build failed (build macros): " + e);
					}
				}

				try {
					macroSession = MacroRuntimeMode.openSession(macroRuntimeMode);
				} catch (e:String) {
					closeMacroSession();
					return error("macro runtime required for @:build, but could not be started: " + e);
				}
			}

			final out2 = new Array<ResolvedModule>();
			for (m in resolved) {
				final pm = ResolvedModule.getParsed(m);
				final exprs = collectBuildMacroExprs(pm.getSource(), ResolvedModule.getModulePath(m));
				if (exprs.length == 0) {
					out2.push(m);
					continue;
				}

				final modulePath = ResolvedModule.getModulePath(m);
				// Reset any previously-emitted fields for this module for deterministic behavior.
				hxhx.macro.MacroState.clearBuildFields(modulePath);
				hxhx.macro.MacroState.setDefine("HXHX_BUILD_MODULE", modulePath);
				hxhx.macro.MacroState.setDefine("HXHX_BUILD_FILE", ResolvedModule.getFilePath(m));
				hxhx.macro.MacroState.setBuildFieldsPayload(buildFieldsPayloadForParsed(pm));

				for (i in 0...exprs.length) {
					final expr = exprs[i];
					Sys.println("build_macro[" + modulePath + "][" + i + "]=" + expr);
					try {
						// The macro effect is communicated via reverse RPC `compiler.emitBuildFields`.
						Sys.println("build_macro_run[" + modulePath + "][" + i + "]=" + macroSession.run(expr));
					} catch (e:String) {
						closeMacroSession();
						return error("build macro failed: " + modulePath + ": " + e);
					}
				}

				final snippets = hxhx.macro.MacroState.listBuildFields(modulePath);
				Sys.println("build_fields[" + modulePath + "]=" + snippets.length);
				if (snippets.length == 0) {
					out2.push(m);
					continue;
				}

				final gen = try parseGeneratedMembers(snippets) catch (e:String) {
					closeMacroSession();
					return error("build fields parse failed: " + modulePath + ": " + e);
				}

				final oldDecl = pm.getDecl();
				final oldCls = HxModuleDecl.getMainClass(oldDecl);
				// Stage4 build-macro bring-up: treat emitted members as "add or replace".
				//
				// Why
				// - Upstream build macros commonly return a full `Array<Field>` where some entries
				//   are modifications of existing members.
				// - Our transport is still raw member snippets, so we implement a conservative
				//   replacement model: if the emitted snippet parses to a member with the same
				//   name as an existing one, we drop the existing member and keep the new one.
				//
				// Non-goal
				// - True deletion by omission is not supported yet.
				inline function fnKey(fn:HxFunctionDecl):String {
					// In our Stage3 bootstrap AST, `static`/visibility parsing is still incomplete for
					// some member forms. For replacement semantics we therefore match by name only.
					return HxFunctionDecl.getName(fn);
				}
				inline function fieldKey(f:HxFieldDecl):String {
					return HxFieldDecl.getName(f);
				}

				final genFnKeys:Map<String, Bool> = new Map();
				for (fn in gen.functions)
					genFnKeys.set(fnKey(fn), true);
				final genFieldKeys:Map<String, Bool> = new Map();
				for (f in gen.fields)
					genFieldKeys.set(fieldKey(f), true);

				final keptFns = new Array<HxFunctionDecl>();
				for (fn in HxClassDecl.getFunctions(oldCls)) {
					if (!genFnKeys.exists(fnKey(fn)))
						keptFns.push(fn);
				}
				final mergedFns = keptFns.concat(gen.functions);

				final keptFields = new Array<HxFieldDecl>();
				for (f in HxClassDecl.getFields(oldCls)) {
					if (!genFieldKeys.exists(fieldKey(f)))
						keptFields.push(f);
				}
				final mergedFields = keptFields.concat(gen.fields);
				final newCls = new HxClassDecl(HxClassDecl.getName(oldCls), HxClassDecl.getHasStaticMain(oldCls), mergedFns, mergedFields,
					HxClassDecl.getExtendsPath(oldCls));
				final newClasses = new Array<HxClassDecl>();
				for (c in HxModuleDecl.getClasses(oldDecl)) {
					if (HxClassDecl.getName(c) == HxClassDecl.getName(oldCls)) {
						newClasses.push(newCls);
					} else {
						newClasses.push(c);
					}
				}
				final newDecl = new HxModuleDecl(HxModuleDecl.getPackagePath(oldDecl), HxModuleDecl.getImports(oldDecl), newCls, newClasses,
					HxModuleDecl.getHeaderOnly(oldDecl), HxModuleDecl.getHasToplevelMain(oldDecl));
				final newParsed = new ParsedModule(pm.getSource(), newDecl, pm.getFilePath());
				out2.push(new ResolvedModule(modulePath, ResolvedModule.getFilePath(m), newParsed));
			}
			resolvedForTyping = out2;
		} else if (typeOnly && anyBuildMacros) {
			// Diagnostic mode: surface build macro expressions, but do not attempt to execute them.
			var i = 0;
			for (m in resolved) {
				final pm = ResolvedModule.getParsed(m);
				final exprs = collectBuildMacroExprs(pm.getSource(), ResolvedModule.getModulePath(m));
				for (e in exprs) {
					Sys.println("build_macro_skipped[" + i + "]=" + ResolvedModule.getModulePath(m) + ":" + e);
					i += 1;
				}
			}
		}

		// Stage4 bring-up: expression macro expansion pass (pre-typing).
		//
		// This is a small rung that only expands allowlisted exact call strings, and only supports
		// a tiny returned expression subset (parsed by `HxParser.parseExprText`).
		if (!typeOnly && exprMacros.length > 0) {
			if (macroSession == null) {
				closeMacroSession();
				return error("expression macro expansion requested (HXHX_EXPR_MACROS), but no macro host session is available");
			}
			#if (hxhx_stage0_no_hx_parser || hxhx_stage0_no_expr_macros)
			closeMacroSession();
			return error("expression macro expansion unavailable in stage0 profiling lane");
			#else
			final exp = ExprMacroExpander.expandResolvedModules(resolvedForTyping, macroSession, exprMacros);
			resolvedForTyping = exp.modules;
			Sys.println("expr_macros_expanded=" + exp.expandedCount);
			#end
		}

		final typerIndex = TyperIndex.build(resolvedForTyping);
		final moduleLoader = new ModuleLoader(classPaths, definesMap, typerIndex, function(typePath:String):Bool {
			return dispatchOnTypeNotFoundHooks(macroSession, typePath);
		}, !noEmit);
		moduleLoader.markResolvedAlready(resolvedForTyping);

		// Stage3 diagnostic mode: type the full resolved graph (best-effort), then stop.
		//
		// Why
		// - Upstream-ish workloads can look like they "pass" if we only type the root module.
		// - Gate1 bring-up needs failures to move from "frontend seam" to "missing typer features".
		//
		// What
		// - Runs `TyperStage.typeModule` for every resolved module.
		// - Does not emit OCaml or build an executable.
		// - Still executes macro hooks (when present) so macro-side failures surface deterministically.
		if (typeOnly) {
			var typedCount = 0;
			var headerOnlyCount = 0;
			var parsedMethodsTotal = 0;
			var unsupportedExprsTotal = 0;
			var unsupportedFilesCount = 0;
			final traceUnsupported = isTrueEnv("HXHX_TRACE_UNSUPPORTED");
			var unsupportedRawCount = 0;
			var unsupportedFnCount = 0;
			final rootFilePath = ResolvedModule.getFilePath(resolved[0]);
			var rootTyped:Null<TypedModule> = null;
			// Worklist so the typer can lazily load modules on demand.
			final toType = resolvedForTyping.copy();
			var cursor = 0;
			while (cursor < toType.length) {
				final m = toType[cursor];
				cursor += 1;
				try {
					final pm = ResolvedModule.getParsed(m);
					final unsupportedInFile = countUnsupportedExprsInModule(pm);
					unsupportedExprsTotal += unsupportedInFile;
					if (unsupportedInFile > 0) {
						Sys.println("unsupported_file[" + unsupportedFilesCount + "]=" + ResolvedModule.getFilePath(m) + " header_only="
							+ bool01(HxModuleDecl.getHeaderOnly(pm.getDecl())) + " unsupported_exprs=" + unsupportedInFile);
						if (traceUnsupported) {
							// Per-function summary so unsupported shapes are actionable even when raw payloads
							// come from native protocol rungs (which may not preserve source locations yet).
							final cls = HxModuleDecl.getMainClass(pm.getDecl());
							for (fn in HxClassDecl.getFunctions(cls)) {
								final fnUnsupported = countUnsupportedExprsInFunction(fn);
								if (fnUnsupported <= 0)
									continue;
								Sys.println("unsupported_fn[" + unsupportedFnCount + "]=" + ResolvedModule.getFilePath(m) + ":" + HxFunctionDecl.getName(fn)
									+ " unsupported_exprs=" + fnUnsupported);
								unsupportedFnCount += 1;
								if (unsupportedFnCount >= 50)
									break;
							}
							for (raw in collectUnsupportedExprRawInModule(pm, 20)) {
								final escaped = escapeOneLine(raw);
								Sys.println("unsupported_expr[" + unsupportedRawCount + "]=" + ResolvedModule.getFilePath(m) + ":raw=" + escaped + " len="
									+ (raw == null ? 0 : raw.length));
								unsupportedRawCount += 1;
								if (unsupportedRawCount >= 50)
									break;
							}
						}
						unsupportedFilesCount += 1;
					}
					if (HxModuleDecl.getHeaderOnly(pm.getDecl())) {
						Sys.println("header_only_file[" + headerOnlyCount + "]=" + ResolvedModule.getFilePath(m));
						headerOnlyCount += 1;
					}
					parsedMethodsTotal += HxClassDecl.getFunctions(HxModuleDecl.getMainClass(pm.getDecl())).length;
					final typed = TyperStage.typeResolvedModule(m, typerIndex, moduleLoader);
					if (ResolvedModule.getFilePath(m) == rootFilePath)
						rootTyped = typed;
					typedCount += 1;
				} catch (e:TyperError) {
					closeMacroSession();
					final rawDiagnostic = rawTyperDiagnostic(e);
					if (rawDiagnostic != null)
						return haxeDiagnosticError(rawDiagnostic);
					return error("type failed: " + ResolvedModule.getFilePath(m) + ": " + formatException(e));
				} catch (e:String) {
					closeMacroSession();
					return error("type failed: " + ResolvedModule.getFilePath(m) + ": " + e);
				}
				// Incorporate any newly loaded modules into the worklist.
				for (nm in moduleLoader.drainNewModules()) {
					resolvedForTyping.push(nm);
					toType.push(nm);
				}
			}

			// Deterministic typer summary for the root module (bring-up diagnostics).
			if (rootTyped != null) {
				final fns = rootTyped.getEnv().getMainClass().getFunctions();
				for (i in 0...fns.length) {
					final tf = fns[i];
					final locals = tf.getLocals();
					final localsParts = new Array<String>();
					for (l in locals)
						localsParts.push(l.getName() + ":" + l.getType().toString());
					final params = tf.getParams();
					final paramParts = new Array<String>();
					for (p in params)
						paramParts.push(p.getName() + ":" + p.getType().toString());
					Sys.println("typed_fn[" + i + "]=" + tf.getName() + " args=" + paramParts.join(",") + " locals=" + localsParts.join(",") + " ret="
						+ tf.getReturnType().toString() + " inferred=" + tf.getReturnExprType().toString());
				}
			}

			final typeOnlyHookError = Stage3HookSupport.runStandardMacroHooks(macroSession);
			if (typeOnlyHookError != null) {
				closeMacroSession();
				return error(typeOnlyHookError);
			}

			closeMacroSession();
			Sys.println("typed_modules=" + typedCount);
			Sys.println("header_only_modules=" + headerOnlyCount);
			Sys.println("parsed_methods_total=" + parsedMethodsTotal);
			Sys.println("unsupported_exprs_total=" + unsupportedExprsTotal);
			Sys.println("unsupported_files=" + unsupportedFilesCount);
			Sys.println("stage3=type_only_ok");
			return 0;
		}

		// Stage3 "real compiler" rung: type the full resolved graph (best-effort),
		// then emit/build an executable from the typed program.
		//
		// No-emit is a compiler-latency and semantic marker lane, not an emission preparation lane:
		// keep it closer to upstream `--no-output` by typing explicit roots plus anything the lazy
		// loader discovers. `--hxhx-type-only` remains the exhaustive full-graph diagnostic rung.
		final initialModulesToType = if (noEmit) {
			final rootSet = new Map<String, Bool>();
			for (root in roots)
				if (root != null && root.length > 0)
					rootSet.set(root, true);
			final rootModules = new Array<ResolvedModule>();
			for (m in resolvedForTyping) {
				final modulePath = ResolvedModule.getModulePath(m);
				if (rootSet.exists(modulePath))
					rootModules.push(m);
			}
			if (rootModules.length > 0)
				rootModules
			else
				[resolvedForTyping[0]];
		} else {
			resolvedForTyping.copy();
		}
		final typedModules = new Array<TypedModule>();
		// Worklist so the typer can lazily load modules on demand. Newly loaded modules are typed and
		// included in the emitted program so `dune build` does not fail on missing modules.
		final toType = initialModulesToType.copy();
		var cursor = 0;
		while (cursor < toType.length) {
			final m = toType[cursor];
			cursor += 1;
			try {
				typedModules.push(TyperStage.typeResolvedModule(m, typerIndex, moduleLoader));
			} catch (e:TyperError) {
				closeMacroSession();
				final rawDiagnostic = rawTyperDiagnostic(e);
				if (rawDiagnostic != null)
					return haxeDiagnosticError(rawDiagnostic);
				return error("type failed: " + ResolvedModule.getFilePath(m) + ": " + formatException(e));
			} catch (e:String) {
				closeMacroSession();
				return error("type failed: " + ResolvedModule.getFilePath(m) + ": " + e);
			}
			for (nm in moduleLoader.drainNewModules()) {
				resolvedForTyping.push(nm);
				toType.push(nm);
			}
		}

		final hookError = Stage3HookSupport.runStandardMacroHooks(macroSession);
		if (hookError != null) {
			closeMacroSession();
			return error(hookError);
		}

		final providerDefines = allDefines.copy();
		for (name in hxhx.macro.MacroState.listDefineNames()) {
			final value = hxhx.macro.MacroState.definedValue(name);
			if (value == null || value.length == 0 || value == "1") {
				providerDefines.push(name);
			} else {
				providerDefines.push(name + "=" + value);
			}
		}
		try {
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=before_load_dynamic_backend_providers");
			}
			loadDynamicBackendProviders(providerDefines);
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=after_load_dynamic_backend_providers");
			}
		} catch (e:String) {
			closeMacroSession();
			return error("backend provider setup failed: " + e);
		}
		final backend = try {
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=before_resolve_builtin_backend id=" + backendId);
			}
			resolveBuiltinBackend(backendId);
		} catch (e:String) {
			closeMacroSession();
			return error("backend setup failed: " + e);
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=after_resolve_builtin_backend");
		}
		final selected = BackendRegistry.descriptorForTarget(backendId);
		if (isTrueEnv("HXHX_TRACE_BACKEND_SELECTION")) {
			if (selected == null) {
				Sys.println("backend_selected_impl=<unknown>");
			} else {
				Sys.println("backend_selected_impl=" + selected.implId);
			}
		}
		if (selected == null) {
			closeMacroSession();
			return error("backend descriptor not found after selection: " + backendId);
		}
		final backendCaps = selected.capabilities;
		final supportsCustomOutputFile:Bool = backendCaps.supportsCustomOutputFile == true;
		final supportsBuildExecutable:Bool = backendCaps.supportsBuildExecutable == true;

		// Diagnostic rung: stop after macros, typing, and backend selection so we can iterate Stage4
		// macro model and Stage3 typer coverage without paying IR expansion or backend emit costs.
		if (noEmit) {
			if (backendCaps.supportsNoEmit != true) {
				closeMacroSession();
				return error("backend does not support --hxhx-no-emit: " + backendId);
			}
			if (backendId == "java-native") {
				final metadataDiagnostic = JavaNoEmitDiagnostics.jvmAnnotationMetadataDiagnostic(typedModules);
				if (metadataDiagnostic != null) {
					closeMacroSession();
					return haxeDiagnosticError(metadataDiagnostic);
				}
				final abstractDiagnostic = JavaNoEmitDiagnostics.abstractOverloadImplementationDiagnostic(typedModules);
				if (abstractDiagnostic != null) {
					closeMacroSession();
					return haxeDiagnosticError(abstractDiagnostic);
				}
				final overloadDiagnostic = JavaNoEmitDiagnostics.overloadCollisionDiagnostic(typedModules);
				if (overloadDiagnostic != null) {
					closeMacroSession();
					return haxeDiagnosticError(overloadDiagnostic);
				}
			}

			for (name in hxhx.macro.MacroState.listDefineNames()) {
				if (StringTools.startsWith(name, "HXHX_")) {
					Sys.println("macro_define2[" + name + "]=" + hxhx.macro.MacroState.definedValue(name));
				}
			}

			var headerOnlyCount = 0;
			var unsupportedExprsTotal = 0;
			var unsupportedFilesCount = 0;
			final traceUnsupported = isTrueEnv("HXHX_TRACE_UNSUPPORTED");
			var unsupportedRawCount = 0;
			var unsupportedFnCount = 0;
			var unsupportedFileIndex = 0;
			for (typed in typedModules) {
				final pm = typed.getParsed();
				if (HxModuleDecl.getHeaderOnly(pm.getDecl()))
					headerOnlyCount += 1;
				final unsupportedInFile = countUnsupportedExprsInModule(pm);
				unsupportedExprsTotal += unsupportedInFile;
				if (unsupportedInFile > 0) {
					unsupportedFilesCount += 1;
					Sys.println("unsupported_file[" + unsupportedFileIndex + "]=" + pm.getFilePath() + " header_only="
						+ bool01(HxModuleDecl.getHeaderOnly(pm.getDecl())) + " unsupported_exprs=" + unsupportedInFile);
					unsupportedFileIndex += 1;
					if (traceUnsupported) {
						final cls = HxModuleDecl.getMainClass(pm.getDecl());
						for (fn in HxClassDecl.getFunctions(cls)) {
							final fnUnsupported = countUnsupportedExprsInFunction(fn);
							if (fnUnsupported <= 0)
								continue;
							Sys.println("unsupported_fn[" + unsupportedFnCount + "]=" + pm.getFilePath() + ":" + HxFunctionDecl.getName(fn)
								+ " unsupported_exprs=" + fnUnsupported);
							unsupportedFnCount += 1;
							if (unsupportedFnCount >= 50)
								break;
						}
						for (raw in collectUnsupportedExprRawInModule(pm, 20)) {
							final escaped = escapeOneLine(raw);
							Sys.println("unsupported_expr[" + unsupportedRawCount + "]=" + pm.getFilePath() + ":raw=" + escaped + " len="
								+ (raw == null ? 0 : raw.length));
							unsupportedRawCount += 1;
							if (unsupportedRawCount >= 50)
								break;
						}
					}
				}
			}
			closeMacroSession();
			Sys.println("typed_modules=" + typedModules.length);
			Sys.println("header_only_modules=" + headerOnlyCount);
			Sys.println("unsupported_exprs_total=" + unsupportedExprsTotal);
			Sys.println("unsupported_files=" + unsupportedFilesCount);
			Sys.println("stage3=no_emit_ok");
			return 0;
		}

		// Collect generated modules after hooks.
		final generated = new Array<MacroExpandedModule.GeneratedOcamlModule>();
		for (name in hxhx.macro.MacroState.listOcamlModuleNames()) {
			generated.push({name: name, source: hxhx.macro.MacroState.getOcamlModuleSource(name)});
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=before_expand typed_modules=" + typedModules.length + " generated_modules=" + generated.length);
		}
		final expanded = MacroStage.expandProgram(typedModules, generated);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=after_expand");
		}

		// Bring-up diagnostics: dump HXHX_* defines again after hooks.
		for (name in hxhx.macro.MacroState.listDefineNames()) {
			if (StringTools.startsWith(name, "HXHX_")) {
				Sys.println("macro_define2[" + name + "]=" + hxhx.macro.MacroState.definedValue(name));
			}
		}

		var emitted = new EmitResult("", [], false);
		try {
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=before_output_file_hint");
			}
			final outputFileHint = if (supportsCustomOutputFile && targetOutputHintRaw != null && targetOutputHintRaw.length > 0) {
				Path.isAbsolute(targetOutputHintRaw) ? Path.normalize(targetOutputHintRaw) : absFromCwd(cwd, targetOutputHintRaw);
			} else {
				null;
			}
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=after_output_file_hint");
				Sys.println("stage3_driver=before_backend_context");
			}
			final outputDirAbs = if (targetOutputDirHintRaw != null && targetOutputDirHintRaw.length > 0) {
				Path.isAbsolute(targetOutputDirHintRaw) ? Path.normalize(targetOutputDirHintRaw) : absFromCwd(cwd, targetOutputDirHintRaw);
			} else {
				outAbs;
			}
			final context = new BackendContext(outputDirAbs, outputFileHint, parsedMain, emitFullBodies, supportsBuildExecutable, definesMap);
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=after_backend_context");
				Sys.println("stage3_driver=before_emit_trace_backend_id");
			}
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=after_emit_trace_backend_id");
				Sys.println("stage3_driver=before_emit backend=" + backendId + " typed_modules=" + typedModules.length + " out=" + outputDirAbs);
			}
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=emitWithBackend_before_genir_boundary");
			}
			final expandedProgram = GenIrBoundary.fromDynamic(cast expanded);
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=emitWithBackend_after_genir_boundary");
				Sys.println("stage3_driver=emitWithBackend_before_dispatch_boundary");
			}
			emitted = BackendDispatchBoundary.emit(backend, expandedProgram, context);
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=emitWithBackend_after_dispatch_boundary");
			}
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				Sys.println("stage3_driver=after_emit entry=" + emitted.entryPath + " built_executable=" + bool01(emitted.builtExecutable));
			}
		} catch (e:String) {
			closeMacroSession();
			return error("emit failed: " + e);
		} catch (e:Dynamic) {
			// Exception boundary: target backends may throw haxe.Exception or other non-string
			// values. Keep Stage3 diagnostics structured instead of leaking an OCaml runtime fatal.
			closeMacroSession();
			return error("emit failed: " + formatDynamicException(e));
		}

		Sys.println("stage3=ok");
		Sys.println("outDir=" + outAbs);
		if (emitted.builtExecutable) {
			Sys.println("exe=" + emitted.entryPath);
		} else {
			Sys.println("artifact=" + emitted.entryPath);
		}

		closeMacroSession();

		if (noRun) {
			Sys.println("run=skipped");
			return 0;
		}

		if (!emitted.builtExecutable) {
			if (backendId == "java-native" && parsedHadCmd) {
				final cmdCode = runSafeJavaJarHookForArtifact(parsedCmdCommands, cwd, emitted.entryPath);
				if (cmdCode != null) {
					if (cmdCode != 0)
						return error("command hook failed with exit code " + Std.string(cmdCode));
					Sys.println("stage3=cmd_ok");
					return 0;
				}
			}
			if (backendId == "python-native" && parsedHadCmd) {
				final cmdCode = runSafePythonHookForArtifact(parsedCmdCommands, cwd, emitted.entryPath);
				if (cmdCode != null) {
					if (cmdCode != 0)
						return error("command hook failed with exit code " + Std.string(cmdCode));
					Sys.println("stage3=cmd_ok");
					return 0;
				}
			}
			if (backendId == "js-native") {
				if (!canRunNode()) {
					Sys.println("run=skipped_node_missing");
					return 0;
				}
				final jsCode = Sys.command("node", [emitted.entryPath]);
				if (jsCode != 0)
					return error("node run failed with exit code " + jsCode);
				Sys.println("run=ok");
				return 0;
			}
			Sys.println("run=skipped_non_executable_backend");
			return 0;
		}

		final code = Sys.command(emitted.entryPath, []);
		if (code != 0)
			return error("built executable failed with exit code " + code);
		Sys.println("run=ok");
		return 0;
	}

	public static function run(args:Array<String>):Int {
		final wait = try {
			parseWaitMode(args);
		} catch (e:String) {
			return error(e);
		}

		if (wait.waitMode != null) {
			if (wait.waitMode == "stdio")
				return runWaitStdio(wait.rest);
			return runWaitSocket(wait.waitMode, wait.rest);
		}

		final connect = try {
			parseConnectMode(wait.rest);
		} catch (e:String) {
			return error(e);
		}

		if (connect.connectMode != null) {
			return runConnect(connect.connectMode, connect.rest);
		}

		final global = try {
			parseGlobalStage3Flags(connect.rest);
		} catch (e:String) {
			return error(e);
		}

		final units = Hxml.expandArgsToUnits(global.rest);
		if (units == null)
			return error("failed to expand .hxml args (multi-unit)");

		// Single-unit fast path: keep logs identical for the common bring-up case.
		if (units.length <= 1) {
			return runOne(connect.rest);
		}

		// Multi-unit `.hxml` support: run each unit sequentially.
		//
		// Bootstrap behavior:
		// - Global stage3-only flags (`--hxhx-no-run`, `--hxhx-type-only`, etc.) apply to every unit.
		// - If a global `--hxhx-out <dir>` is provided, we suffix it per-unit to avoid collisions.
		for (idx in 0...units.length) {
			final u = units[idx];
			if (global.backendId == "js-native" && CliRouting.isJsNativeHelperUnit(u)) {
				Sys.println("hxhx(stage3): unit_skipped idx=" + idx + " reason=js_native_neko_cmd_helper args=" + summarizeArgs(u));
				continue;
			}
			final unitArgs = new Array<String>();
			if (global.backendId != null && global.backendId.length > 0) {
				unitArgs.push("--hxhx-backend");
				unitArgs.push(global.backendId);
			}
			if (global.macroRuntimeMode != null && global.macroRuntimeMode.length > 0) {
				unitArgs.push("--hxhx-macro-runtime");
				unitArgs.push(global.macroRuntimeMode);
			}
			if (global.typeOnly)
				unitArgs.push("--hxhx-type-only");
			if (global.noEmit)
				unitArgs.push("--hxhx-no-emit");
			if (global.noRun)
				unitArgs.push("--hxhx-no-run");
			if (global.emitFullBodies)
				unitArgs.push("--hxhx-emit-full-bodies");

			if (global.outDir != null && global.outDir.length > 0 && !hasFlag(u, "--hxhx-out")) {
				unitArgs.push("--hxhx-out");
				unitArgs.push(global.outDir + "_u" + idx);
			}
			for (a in u)
				unitArgs.push(a);

			if (Sys.getEnv("HXHX_TRACE_UNITS") == "1") {
				final main = findFlagValue(u, "-main", "--main");
				final cp = findManyFlagValues(u, "-cp", "--class-path", "-p");
				Sys.println("hxhx(stage3): unit_begin idx=" + idx + " main=" + (main == null ? "<none>" : main) + " cp=" + cp.join(",") + " args="
					+ summarizeArgs(u));
			}

			final code = runOne(unitArgs);
			if (code != 0)
				return code;
		}
		return 0;
	}

	static function findFlagValue(args:Array<String>, a:String, b:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			final t = args[i];
			if ((t == a || t == b) && i + 1 < args.length)
				return args[i + 1];
			i++;
		}
		return null;
	}

	static function findManyFlagValues(args:Array<String>, a:String, b:String, ?c:String):Array<String> {
		final out = new Array<String>();
		var i = 0;
		while (i < args.length) {
			final t = args[i];
			final match = (t == a || t == b || (c != null && t == c));
			if (match && i + 1 < args.length) {
				out.push(args[i + 1]);
				i += 2;
				continue;
			}
			i++;
		}
		return out;
	}

	static function summarizeArgs(args:Array<String>):String {
		final joined = args.join(" ");
		final maxLen = 160;
		if (joined.length <= maxLen)
			return joined;
		return joined.substr(0, maxLen) + "...";
	}
}
