package hxhx;

import hxhx.runtime.NullableRuntimeString;
import haxe.io.Eof;
import hxhx.Stage1Compiler.Stage1Args;
#if !hxhx_stage0_no_external_macro_host
import hxhx.macro.MacroHostClient;
#end
import hxhx.macro.MacroRuntimeMode;
import hxhx.macro.MacroRuntimeSession;

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

	static function runWaitStdio(baseArgs:Array<String>):Int {
		return Stage3WaitServer.runWaitStdio(baseArgs, runRequest, error);
	}

	/**
		Run Stage3 as a persistent `--wait <host:port>` socket server.

		Implementation note
		- This path uses a small OCaml runtime bridge (`HxHxCompilerServer`) because the current
		  bootstrap codegen does not yet support `sys.net.Socket` property access (`input`/`output`)
		  from Stage3 Haxe code.
		- The bridge only accepts socket frames and returns response bytes. Haxe decodes every
		  ordinary compile or display request and sends it through the shared dispatcher.
	**/
	static function runWaitSocket(mode:String, baseArgs:Array<String>):Int {
		return Stage3WaitServer.runWaitSocket(mode, baseArgs, runRequest, error);
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

	static function absFromCwd(cwd:String, path:String):String {
		return Stage3PathSupport.absFromCwd(cwd, path);
	}

	static function collectBackendResources(specs:Array<String>, cwd:String):Array<backend.BackendResource> {
		final out = new Array<backend.BackendResource>();
		for (spec in specs) {
			if (spec == null || spec.length == 0)
				continue;
			final separator = spec.lastIndexOf("@");
			final filePart = separator >= 0 ? spec.substr(0, separator) : spec;
			final namePart = separator >= 0 ? spec.substr(separator + 1) : haxe.io.Path.withoutDirectory(filePart);
			if (filePart.length == 0 || namePart.length == 0)
				throw "invalid --resource spec: " + spec;
			final path = absFromCwd(cwd, filePart);
			if (!sys.FileSystem.exists(path))
				throw "resource file not found: " + path;
			out.push({name: namePart, data: sys.io.File.getBytes(path)});
		}
		return out;
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

	static function isBuiltinMacroExpr(expr:String):Bool {
		return Stage3MacroHostSupport.isBuiltinMacroExpr(expr);
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

	static function dispatchOnTypeNotFoundHooks(macroSession:Null<MacroRuntimeSession>, typePath:String, ?output:CompilationRequestOutput):Bool {
		return Stage3BuildMacroSupport.dispatchOnTypeNotFoundHooks(macroSession, typePath, output);
	}

	static function runOne(args:Array<String>, requestContext:CompilationRequestContext):Int {
		final requestOutput = requestContext.output;
		hxhx.macro.MacroState.reset();
		requestContext.registerCleanup("macro-state", hxhx.macro.MacroState.reset);
		Stage3BackendPluginSupport.resetRequestState();
		requestContext.registerCleanup("backend-plugin-state", Stage3BackendPluginSupport.resetRequestState);
		inline function error(msg:String):Int {
			requestOutput.stdoutLine("hxhx(stage3): " + msg);
			return 2;
		}
		inline function haxeDiagnosticError(msg:String):Int {
			requestOutput.stderrLine(msg);
			return 1;
		}

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
		if (requestContext.isServerRequest && !noRun)
			return error("server compile requests must currently include --hxhx-no-run so target program output cannot escape the client response");
		final customizations = try {
			Stage3CustomizationSupport.normalize(g.customizations);
		} catch (e:String) {
			return error(e);
		}
		final rest = g.rest;
		if (!requestContext.checkpoint("setup"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		MacroRuntimeMode.emitMarker(macroRuntimeMode, requestOutput);
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
		final parsedResourceSpecs = Stage1Args.getResourceSpecs(parsed);
		final parsedCwd = Stage1Args.getCwd(parsed);
		final parsedClassPaths = Stage1Args.getClassPaths(parsed);
		final parsedLibs = Stage1Args.getLibs(parsed);
		final parsedHadCmd = Stage1Args.getHadCmd(parsed);
		final parsedCmdCommands = Stage1Args.getCmdCommands(parsed);
		final parsedHadRun = Stage1Args.getHadRun(parsed);
		final parsedRunArgs = Stage1Args.getRunArgs(parsed);
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

		// Upstream allows invocations without `-main`:
		// - "macro-only" compilation (`--macro ...`) and/or
		// - compile-time suites that pass "dot paths" as positional args (type/module roots).
		//
		// Stage3 bring-up supports this by deriving resolver roots in this priority order:
		// 1) explicit `-main`
		// 2) positional roots (`<pack.TypeName>` args)
		// 3) first `--macro` entrypoint's type path (before the final `.method(...)`)
		final initialRoots = Stage3Args.initialRoots(parsedMain, parsedRoots, parsedMacros);
		if (initialRoots.missingMainFromMacro)
			return error("missing -main <TypeName>");
		final roots0 = initialRoots.roots;
		final displayRequest = Stage1Args.getDisplayRequest(parsed);

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
				requestOutput.stdoutLine("macro_skipped[" + i + "]=" + parsedMacros[i]);
			}
		}

		// Stage4 bring-up: expression macro allowlist.
		//
		// These are call sites in *normal code* (not CLI `--macro`) that we will attempt to expand
		// before typing by asking the macro host for a replacement expression snippet.
		final exprMacros = Stage3MacroHostSupport.exprMacroAllowlistFromEnv();

		var macroSession:Null<MacroRuntimeSession> = null;

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
			final commandOnlyError = Stage3RunSupport.runCommandOnlyUnit(parsedHadCmd, parsedCmdCommands, cwd, requestOutput);
			if (commandOnlyError != null)
				return error(commandOnlyError);
			return 0;
		}

		final outAbs = absFromCwd(cwd, (outDir.length > 0 ? outDir : "out_stage3"));
		final backendResources = try {
			collectBackendResources(parsedResourceSpecs, cwd);
		} catch (e:String) {
			return error(e);
		}

		// Macro state exists even in non-macro runs; it is a no-op unless the macro host calls back.
		final libsResolved = Stage3SetupSupport.resolveLibraries(parsedLibs, cwd);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			requestOutput.stdoutLine("stage3_driver=libs_resolved count=" + libsResolved.length);
			for (i in 0...libsResolved.length) {
				final spec = libsResolved[i];
				requestOutput.stdoutLine("stage3_driver=lib[" + i + "].class_paths=" + spec.classPaths.join("|"));
				requestOutput.stdoutLine("stage3_driver=lib[" + i + "].unknown_args=" + spec.unknownArgs.join("|"));
			}
		}
		final libDefines = Stage3SetupSupport.collectLibraryDefines(libsResolved);
		final allDefines = parsedDefines.concat(libDefines);
		hxhx.macro.MacroState.seedFromCliDefines(allDefines);
		final macroStdPaths = Stage3SetupSupport.collectMacroStdPaths(cwd);
		final backendTargetDefine = targetDefineForBackend(backendId);
		hxhx.macro.MacroState.seedCompilerConfiguration(args, macroStdPaths, backendTargetDefine);
		hxhx.macro.MacroState.setGeneratedHxDir(haxe.io.Path.join([outAbs, "_gen_hx"]));

		final libMacros = Stage3SetupSupport.collectLibraryMacros(libsResolved);
		final runHaxelibMacros = isTrueEnv("HXHX_RUN_HAXELIB_MACROS");

		final macroHostClassPaths = Stage3SetupSupport.macroHostClassPaths(parsedClassPaths, libsResolved, cwd);

		if (!requestContext.checkpoint("macros"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		final cliMacroRun = Stage3MacroHostSupport.runCliMacrosIfNeeded(macroRuntimeMode, typeOnly, hasConfiguredExternalMacroHostExe(), parsedMacros,
			exprMacros, runHaxelibMacros, libMacros, macroHostClassPaths, requestOutput);
		if (cliMacroRun.error != null) {
			return error(cliMacroRun.error);
		}
		macroSession = cliMacroRun.session;
		function closeMacroSession():Void {
			if (macroSession != null) {
				macroSession.close();
				macroSession = null;
			}
		}
		requestContext.registerCleanup("macro-session", closeMacroSession);

		final classPaths = Stage3SetupSupport.projectClassPaths(parsedClassPaths, libsResolved, cwd);

		// Defines available for conditional compilation filtering.
		//
		// Notes
		// - CLI `-D` defines were seeded into MacroState at the start of the run.
		// - Macro-time `Compiler.define(...)` calls (reverse RPC) also populate MacroState.
		// - ResolverStage will use this map to strip inactive `#if` branches before parsing.
		final definesMap = try {
			Stage3SetupSupport.buildDefinesMap(allDefines, backendTargetDefine, backendId);
		} catch (e:String) {
			closeMacroSession();
			return error(e);
		}

		final roots = roots0.concat(hxhx.macro.MacroState.listIncludedModules());
		if (!requestContext.checkpoint("resolution"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
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
		if (!requestContext.checkpoint("typing"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		requestOutput.stdoutLine("resolved_modules=" + resolved.length);
		if (backendId == "java-native") {
			final overloadDiagnostic = JavaNoEmitDiagnostics.overloadCollisionDiagnosticForResolved(resolved);
			if (overloadDiagnostic != null) {
				closeMacroSession();
				return haxeDiagnosticError(overloadDiagnostic);
			}
		}
		if (backendId == "cs-native") {
			final csDiagnostic = CSharpNoEmitDiagnostics.diagnosticForResolved(resolved);
			if (csDiagnostic != null) {
				closeMacroSession();
				return haxeDiagnosticError(csDiagnostic);
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
					if (!requestContext.checkpoint("macros"))
						return CompilationRequestContext.CANCELLED_EXIT_CODE;
					final expr = exprs[i];
					requestOutput.stdoutLine("build_macro[" + modulePath + "][" + i + "]=" + expr);
					try {
						// The macro effect is communicated via reverse RPC `compiler.emitBuildFields`.
						requestOutput.stdoutLine("build_macro_run[" + modulePath + "][" + i + "]=" + macroSession.run(expr));
					} catch (e:String) {
						closeMacroSession();
						return error("build macro failed: " + modulePath + ": " + e);
					}
				}

				final snippets = hxhx.macro.MacroState.listBuildFields(modulePath);
				requestOutput.stdoutLine("build_fields[" + modulePath + "]=" + snippets.length);
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
					HxClassDecl.getExtendsPath(oldCls), HxClassDecl.getMetadata(oldCls));
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
					requestOutput.stdoutLine("build_macro_skipped[" + i + "]=" + ResolvedModule.getModulePath(m) + ":" + e);
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
			requestOutput.stdoutLine("expr_macros_expanded=" + exp.expandedCount);
			#end
		}

		final typerIndex = TyperIndex.build(resolvedForTyping);
		final moduleLoader = new ModuleLoader(classPaths, definesMap, typerIndex, function(typePath:String):Bool {
			return dispatchOnTypeNotFoundHooks(macroSession, typePath, requestOutput);
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
			final typedModulesForProgram = new Array<TypedModule>();
			var headerOnlyCount = 0;
			var parsedMethodsTotal = 0;
			var unsupportedExprsTotal = 0;
			var unsupportedFilesCount = 0;
			final traceUnsupported = isTrueEnv("HXHX_TRACE_UNSUPPORTED");
			final unsupportedTraceCounters = Stage3DiagnosticsSupport.newUnsupportedTraceCounters();
			final rootFilePath = ResolvedModule.getFilePath(resolved[0]);
			var rootTyped:Null<TypedModule> = null;
			// Worklist so the typer can lazily load modules on demand.
			final toType = resolvedForTyping.copy();
			var cursor = 0;
			while (cursor < toType.length) {
				if (!requestContext.checkpoint("typing"))
					return CompilationRequestContext.CANCELLED_EXIT_CODE;
				final m = toType[cursor];
				cursor += 1;
				try {
					final pm = ResolvedModule.getParsed(m);
					final unsupportedInFile = Stage3DiagnosticsSupport.reportUnsupportedForParsedModule(pm, ResolvedModule.getFilePath(m),
						unsupportedFilesCount, traceUnsupported, unsupportedTraceCounters, requestOutput);
					unsupportedExprsTotal += unsupportedInFile;
					if (unsupportedInFile > 0)
						unsupportedFilesCount += 1;
					if (HxModuleDecl.getHeaderOnly(pm.getDecl())) {
						requestOutput.stdoutLine("header_only_file[" + headerOnlyCount + "]=" + ResolvedModule.getFilePath(m));
						headerOnlyCount += 1;
					}
					parsedMethodsTotal += Stage3DiagnosticsSupport.parsedMethodCount(pm);
					final typed = TyperStage.typeResolvedModule(m, typerIndex, moduleLoader, true);
					typedModulesForProgram.push(typed);
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
			final sealedTypedModules = try {
				TypedAbstractOperatorLowering.lowerModules(typedModulesForProgram, typerIndex);
			} catch (e:TyperError) {
				closeMacroSession();
				final rawDiagnostic = rawTyperDiagnostic(e);
				if (rawDiagnostic != null)
					return haxeDiagnosticError(rawDiagnostic);
				return error("type failed during shared operator lowering: " + formatException(e));
			} catch (e:String) {
				closeMacroSession();
				return error("type failed during shared operator lowering: " + e);
			}
			rootTyped = null;
			for (typed in sealedTypedModules)
				if (typed.getParsed().getFilePath() == rootFilePath) {
					rootTyped = typed;
					break;
				}

			// Deterministic typer summary for the root module (bring-up diagnostics).
			if (rootTyped != null)
				Stage3DiagnosticsSupport.printTypedFunctionSummary(rootTyped, requestOutput);

			if (!requestContext.checkpoint("hooks"))
				return CompilationRequestContext.CANCELLED_EXIT_CODE;
			final typeOnlyHookError = Stage3HookSupport.runStandardMacroHooks(macroSession, requestOutput);
			if (typeOnlyHookError != null) {
				closeMacroSession();
				return error(typeOnlyHookError);
			}

			closeMacroSession();
			requestOutput.stdoutLine("typed_modules=" + typedCount);
			requestOutput.stdoutLine("header_only_modules=" + headerOnlyCount);
			requestOutput.stdoutLine("parsed_methods_total=" + parsedMethodsTotal);
			requestOutput.stdoutLine("unsupported_exprs_total=" + unsupportedExprsTotal);
			requestOutput.stdoutLine("unsupported_files=" + unsupportedFilesCount);
			Stage3CustomizationSupport.emitTypedSummaryReport(customizations, "type_only", backendId, typedCount, headerOnlyCount, unsupportedExprsTotal,
				unsupportedFilesCount, requestOutput);
			requestOutput.stdoutLine("stage3=type_only_ok");
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
		var typedModules = new Array<TypedModule>();
		// Worklist so the typer can lazily load modules on demand. Newly loaded modules are typed and
		// included in the emitted program so `dune build` does not fail on missing modules.
		final toType = initialModulesToType.copy();
		var cursor = 0;
		while (cursor < toType.length) {
			if (!requestContext.checkpoint("typing"))
				return CompilationRequestContext.CANCELLED_EXIT_CODE;
			final m = toType[cursor];
			cursor += 1;
			try {
				typedModules.push(TyperStage.typeResolvedModule(m, typerIndex, moduleLoader, true));
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
		typedModules = try {
			TypedAbstractOperatorLowering.lowerModules(typedModules, typerIndex);
		} catch (e:TyperError) {
			closeMacroSession();
			final rawDiagnostic = rawTyperDiagnostic(e);
			if (rawDiagnostic != null)
				return haxeDiagnosticError(rawDiagnostic);
			return error("type failed during shared operator lowering: " + formatException(e));
		} catch (e:String) {
			closeMacroSession();
			return error("type failed during shared operator lowering: " + e);
		}

		if (!requestContext.checkpoint("hooks"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		final hookError = Stage3HookSupport.runStandardMacroHooks(macroSession, requestOutput);
		if (hookError != null) {
			closeMacroSession();
			return error(hookError);
		}

		final providerDefines = Stage3BackendPluginSupport.buildProviderDefines(allDefines);
		final backendSelection = try {
			Stage3BackendPluginSupport.selectBackend(backendId, providerDefines, requestOutput);
		} catch (e:String) {
			closeMacroSession();
			return error(e);
		}
		final backend = backendSelection.backend;
		final backendCaps = backendSelection.descriptor.capabilities;
		final supportsCustomOutputFile = backendSelection.supportsCustomOutputFile;
		final supportsBuildExecutable = backendSelection.supportsBuildExecutable;

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

			Stage3DiagnosticsSupport.printHxMacroDefines("macro_define2", requestOutput);

			var headerOnlyCount = 0;
			var unsupportedExprsTotal = 0;
			var unsupportedFilesCount = 0;
			final traceUnsupported = isTrueEnv("HXHX_TRACE_UNSUPPORTED");
			final unsupportedTraceCounters = Stage3DiagnosticsSupport.newUnsupportedTraceCounters();
			var unsupportedFileIndex = 0;
			for (typed in typedModules) {
				final pm = typed.getParsed();
				if (HxModuleDecl.getHeaderOnly(pm.getDecl()))
					headerOnlyCount += 1;
				final unsupportedInFile = Stage3DiagnosticsSupport.reportUnsupportedForParsedModule(pm, pm.getFilePath(), unsupportedFileIndex,
					traceUnsupported, unsupportedTraceCounters, requestOutput);
				unsupportedExprsTotal += unsupportedInFile;
				if (unsupportedInFile > 0) {
					unsupportedFilesCount += 1;
					unsupportedFileIndex += 1;
				}
			}
			closeMacroSession();
			requestOutput.stdoutLine("typed_modules=" + typedModules.length);
			requestOutput.stdoutLine("header_only_modules=" + headerOnlyCount);
			requestOutput.stdoutLine("unsupported_exprs_total=" + unsupportedExprsTotal);
			requestOutput.stdoutLine("unsupported_files=" + unsupportedFilesCount);
			Stage3CustomizationSupport.emitTypedSummaryReport(customizations, "no_emit", backendId, typedModules.length, headerOnlyCount,
				unsupportedExprsTotal, unsupportedFilesCount, requestOutput);
			requestOutput.stdoutLine("stage3=no_emit_ok");
			return 0;
		}

		// Collect generated modules after hooks.
		final generated = new Array<MacroExpandedModule.GeneratedOcamlModule>();
		for (name in hxhx.macro.MacroState.listOcamlModuleNames()) {
			generated.push({name: name, source: hxhx.macro.MacroState.getOcamlModuleSource(name)});
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			requestOutput.stdoutLine("stage3_driver=before_expand typed_modules=" + typedModules.length + " generated_modules=" + generated.length);
		}
		if (!requestContext.checkpoint("normalization"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		final expanded = MacroStage.expandProgram(typedModules, generated);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			requestOutput.stdoutLine("stage3_driver=after_expand");
		}

		// Bring-up diagnostics: dump HXHX_* defines again after hooks.
		Stage3DiagnosticsSupport.printHxMacroDefines("macro_define2", requestOutput);

		final nekoNdllPaths = backendId == "neko-native" ? Stage3SetupSupport.collectNekoNdllPaths(libsResolved, cwd) : [];
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			requestOutput.stdoutLine("stage3_driver=neko_ndll_paths count=" + nekoNdllPaths.length);
			for (i in 0...nekoNdllPaths.length)
				requestOutput.stdoutLine("stage3_driver=neko_ndll_path[" + i + "]=" + nekoNdllPaths[i]);
		}
		if (!requestContext.checkpoint("emission"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		final emitted = try {
			Stage3EmitSupport.emitWithBackend(backend, expanded, backendId, typedModules.length, cwd, outAbs, targetOutputHintRaw, targetOutputDirHintRaw,
				parsedMain, emitFullBodies, supportsCustomOutputFile, supportsBuildExecutable, definesMap, backendResources, nekoNdllPaths, requestOutput);
		} catch (e:String) {
			closeMacroSession();
			return error("emit failed: " + e);
		} catch (e:haxe.Exception) {
			closeMacroSession();
			return error("emit failed: " + formatDynamicException(e));
		} catch (e:Dynamic) {
			// Exception boundary: target backends may throw haxe.Exception or other non-string
			// values. Keep Stage3 diagnostics structured instead of leaking an OCaml runtime fatal.
			closeMacroSession();
			return error("emit failed: " + formatDynamicException(e));
		}
		if (!requestContext.checkpoint("publication"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;

		requestOutput.stdoutLine("stage3=ok");
		requestOutput.stdoutLine("outDir=" + outAbs);
		if (emitted.builtExecutable) {
			requestOutput.stdoutLine("exe=" + emitted.entryPath);
		} else {
			requestOutput.stdoutLine("artifact=" + emitted.entryPath);
		}

		closeMacroSession();

		if (!requestContext.checkpoint("execution"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		final runError = Stage3RunSupport.runEmittedArtifact(backendId, parsedHadCmd, parsedCmdCommands, parsedHadRun, parsedRunArgs, cwd, emitted, noRun,
			nekoNdllPaths, requestOutput);
		if (runError != null)
			return error(runError);
		return 0;
	}

	/**
		Compile one already-decoded request using state owned by that request.

		Server transports and focused lifecycle tests use this boundary. It does not
		retain compiler results between requests; later incremental slices may read
		immutable reusable facts through the context after their identities and
		invalidation rules are proven.
	**/
	public static function runRequest(args:Array<String>, requestContext:CompilationRequestContext):Int {
		if (requestContext == null || requestContext.isClosed())
			throw "compiler request context must be open";
		if (!requestContext.checkpoint("compiler-start"))
			return CompilationRequestContext.CANCELLED_EXIT_CODE;
		return runOne(args, requestContext);
	}

	static function finishRequest(code:Int, context:CompilationRequestContext):Int {
		final cleanupSucceeded = context.close();
		return code == 0 && !cleanupSucceeded ? 2 : code;
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
			final context = CompilationRequestContext.direct();
			if (global.serverReport)
				context.enableBaselineReport();
			final code = runRequest(connect.rest, context);
			return finishRequest(code, context);
		}

		// Multi-unit `.hxml` support: run each unit sequentially.
		//
		// Bootstrap behavior:
		// - Global stage3-only flags (`--hxhx-no-run`, `--hxhx-type-only`, etc.) apply to every unit.
		// - If a global `--hxhx-out <dir>` is provided, we suffix it per-unit to avoid collisions.
		for (idx in 0...units.length) {
			final u = units[idx];
			if (global.backendId == "js-native" && CliRouting.isJsNativeHelperUnit(u)) {
				Sys.println("hxhx(stage3): unit_skipped idx=" + idx + " reason=js_native_neko_cmd_helper args=" + Stage3Args.summarizeArgs(u));
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
			for (customization in global.customizations) {
				unitArgs.push("--hxhx-customization");
				unitArgs.push(customization);
			}
			if (global.typeOnly)
				unitArgs.push("--hxhx-type-only");
			if (global.noEmit)
				unitArgs.push("--hxhx-no-emit");
			if (global.noRun)
				unitArgs.push("--hxhx-no-run");
			if (global.serverReport)
				unitArgs.push("--hxhx-server-report");
			if (global.emitFullBodies)
				unitArgs.push("--hxhx-emit-full-bodies");

			if (global.outDir != null && global.outDir.length > 0 && !hasFlag(u, "--hxhx-out")) {
				unitArgs.push("--hxhx-out");
				unitArgs.push(global.outDir + "_u" + idx);
			}
			for (a in u)
				unitArgs.push(a);

			if (Sys.getEnv("HXHX_TRACE_UNITS") == "1") {
				final main = Stage3Args.findFlagValue(u, "-main", "--main");
				final cp = Stage3Args.findManyFlagValues(u, "-cp", "--class-path", "-p");
				Sys.println("hxhx(stage3): unit_begin idx=" + idx + " main=" + (main == null ? "<none>" : main) + " cp=" + cp.join(",") + " args="
					+ Stage3Args.summarizeArgs(u));
			}

			final context = CompilationRequestContext.direct();
			if (global.serverReport)
				context.enableBaselineReport();
			final code = runRequest(unitArgs, context);
			final finishedCode = finishRequest(code, context);
			if (finishedCode != 0)
				return finishedCode;
		}
		return 0;
	}
}
