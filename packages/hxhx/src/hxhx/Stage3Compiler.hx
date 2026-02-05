package hxhx;

import haxe.io.Path;
import haxe.io.Eof;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroHostClient.MacroHostSession;

/**
	Stage 3 compiler bring-up (`--hxhx-stage3`).

	Why
	- Stage 1 proves we can parse and resolve modules without delegating to Stage0 `haxe`,
	  but it intentionally stops at `--no-output`.
	- Stage 3 is the first rung where `hxhx` behaves like a *real compiler*:
	  parse → resolve → type → emit target code → build an executable.
	- This bring-up path is intentionally narrow: it compiles only the tiny subset we can
	  already type reliably in the bootstrap `hih-compiler` pipeline.

	What (today)
	- Supports a very small subset of the Haxe CLI:
	  - `-cp <dir>` / `-p <dir>` (repeatable)
	  - `-main <Dotted.TypeName>`
	  - `-C / --cwd` (affects relative `-cp` and `--hxhx-out`)
	  - `.hxml` expansion (via `Stage1Args`)
	- Adds one internal flag:
	  - `--hxhx-out <dir>`: where emitted `.ml` and the built executable are written
	- Runs the Stage 2/3 pipeline from `examples/hih-compiler`:
	  - `ResolverStage.parseProject` (transitive import closure)
	  - `TyperStage.typeModule` (literal + identifier return typing)
	  - `EmitterStage.emitToDir` (minimal OCaml emission + `ocamlopt` build)

	Non-goals
	- Full macro integration (`@:build`, typed AST transforms, etc.) is Stage 4.
	- Full Haxe typing is beyond this bring-up rung.

	Gotchas
	- This is an internal bootstrap flag: it must never be forwarded to stage0 `haxe`.
	- The emitted OCaml is intentionally minimal and only supports the acceptance subset.
**/
class Stage3Compiler {
	static function error(msg:String):Int {
		Sys.println("hxhx(stage3): " + msg);
		return 2;
	}

	static function formatException(e:Dynamic):String {
		if (Std.isOfType(e, String)) return cast e;
		return Std.string(e);
	}

	static function haxelibBin():String {
		final v = Sys.getEnv("HAXELIB_BIN");
		return (v == null || v.length == 0) ? "haxelib" : v;
	}

	static function resolveHaxelibPaths(lib:String):Array<String> {
		final paths = new Array<String>();
		final p = new sys.io.Process(haxelibBin(), ["path", lib]);

		try {
			while (true) {
				final raw = p.stdout.readLine();
				final line = StringTools.trim(raw);
				if (line.length == 0) continue;
				// `haxelib path` prints `-D name=ver` lines; only paths matter here.
				if (StringTools.startsWith(line, "-")) continue;
				paths.push(line);
			}
		} catch (_:Eof) {}

		final code = p.exitCode();
		if (code != 0) {
			return throw "haxelib path " + lib + " failed with exit code " + code;
		}
		return paths;
	}

	static function absFromCwd(cwd:String, path:String):String {
		if (path == null || path.length == 0) return cwd;
		return Path.isAbsolute(path) ? Path.normalize(path) : Path.normalize(Path.join([cwd, path]));
	}

	static function inferRepoRootForScripts():String {
		final env = Sys.getEnv("HXHX_REPO_ROOT");
		if (env != null && env.length > 0 && sys.FileSystem.exists(env) && sys.FileSystem.isDirectory(env)) {
			return env;
		}

		final prog = Sys.programPath();
		if (prog == null || prog.length == 0) return "";

		final abs = try sys.FileSystem.fullPath(prog) catch (_:Dynamic) prog;
		var dir = try haxe.io.Path.directory(abs) catch (_:Dynamic) "";
		if (dir == null || dir.length == 0) return "";

		// Walk upwards a few levels looking for `scripts/hxhx/build-hxhx-macro-host.sh`.
		for (_ in 0...10) {
			final candidate = Path.join([dir, "scripts", "hxhx", "build-hxhx-macro-host.sh"]);
			if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate)) return dir;
			final parent = Path.normalize(Path.join([dir, ".."]));
			if (parent == dir) break;
			dir = parent;
		}

		return "";
	}

	static function trim(s:String):String {
		return s == null ? "" : StringTools.trim(s);
	}

	static function isBuiltinMacroExpr(expr:String):Bool {
		final e = trim(expr);
		return StringTools.startsWith(e, "BuiltinMacros.")
			|| StringTools.startsWith(e, "hxhxmacrohost.BuiltinMacros.")
			|| StringTools.startsWith(e, "hxhxmacrohost.BuiltinMacros");
	}

	static function anyNonBuiltinMacro(exprs:Array<String>):Bool {
		for (e in exprs) if (!isBuiltinMacroExpr(e)) return true;
		return false;
	}

	static function shouldAutoBuildMacroHost():Bool {
		final v = trim(Sys.getEnv("HXHX_MACRO_HOST_AUTO_BUILD"));
		return v == "1" || v == "true" || v == "yes";
	}

	static function buildMacroHostExe(repoRoot:String, extraCp:Array<String>, entrypoints:Array<String>):String {
		final script = Path.join([repoRoot, "scripts", "hxhx", "build-hxhx-macro-host.sh"]);
		if (!sys.FileSystem.exists(script)) throw "missing macro host build script: " + script;

		// Environment passed through to the script.
		Sys.putEnv("HXHX_MACRO_HOST_EXTRA_CP", (extraCp != null && extraCp.length > 0) ? extraCp.join(":") : "");
		Sys.putEnv("HXHX_MACRO_HOST_ENTRYPOINTS", (entrypoints != null && entrypoints.length > 0) ? entrypoints.join(";") : "");

		final p = new sys.io.Process("bash", [script]);
		final lines = new Array<String>();
		try {
			while (true) lines.push(p.stdout.readLine());
		} catch (_:Eof) {}

		final code = p.exitCode();
		p.close();
		if (code != 0) throw "macro host build failed with exit code " + code;

		var exe = "";
		for (i in 0...lines.length) {
			final l = trim(lines[i]);
			if (l.length > 0) exe = l;
		}
		if (exe.length == 0) throw "macro host build produced no executable path";
		return exe;
	}

	public static function run(args:Array<String>):Int {
		// Extract stage3-only flags before passing the remainder to `Stage1Args`.
		var outDir = "";
		var typeOnly = false;
		final rest = new Array<String>();
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "--hxhx-out":
					if (i + 1 >= args.length) return error("missing value after --hxhx-out");
					outDir = args[i + 1];
					i += 2;
				case "--hxhx-type-only":
					// Diagnostic bring-up mode: resolve + type the module graph, but don't emit/build.
					typeOnly = true;
					i += 1;
				case _:
					rest.push(a);
					i += 1;
			}
		}

		// Stage3 bring-up is intentionally stricter than a full `haxe` CLI, but it needs to be able to
		// *attempt* upstream-ish hxmls (e.g. Gate1 `compile-macro.hxml`) without failing immediately on
		// non-essential flags. We therefore use Stage1Args in a small permissive mode that ignores
		// a curated set of known upstream flags (e.g. `--interp`, `--debug`, `--dce`, `--resource`).
		final parsed = Stage1Args.parse(rest, true);
		if (parsed == null) return 2;

		if (parsed.main == null || parsed.main.length == 0) return error("missing -main <TypeName>");

		var macroSession:Null<MacroHostSession> = null;
		inline function closeMacroSession():Void {
			if (macroSession != null) {
				macroSession.close();
				macroSession = null;
			}
		}

		final hostCwd = try Sys.getCwd() catch (_:Dynamic) ".";
		final cwd = absFromCwd(hostCwd, parsed.cwd);
			if (!sys.FileSystem.exists(cwd) || !sys.FileSystem.isDirectory(cwd)) {
				return error("cwd is not a directory: " + cwd);
			}

		final outAbs = absFromCwd(cwd, (outDir.length > 0 ? outDir : "out_stage3"));

		final macroHostClassPaths = {
			final base = parsed.classPaths.map(cp -> absFromCwd(cwd, cp));
			final libs = new Array<String>();
			for (lib in parsed.libs) for (p in resolveHaxelibPaths(lib)) libs.push(absFromCwd(cwd, p));
			base.concat(libs);
		}

		if (parsed.macros.length > 0) {
			// Stage3 dev/CI convenience: auto-build a macro host that includes the classpaths needed
			// for the requested CLI `--macro` entrypoints.
			//
			// This is only enabled when `HXHX_MACRO_HOST_AUTO_BUILD=1` (or true/yes) is set.
			//
			// Notes
			// - This is a bring-up tool. It is not meant to be used for production builds.
			// - The produced macro host is built via stage0 `haxe` (the script), not via hxhx itself.
			if (MacroHostClient.resolveMacroHostExePath().length == 0 && shouldAutoBuildMacroHost()) {
				final repoRoot = inferRepoRootForScripts();
				if (repoRoot.length == 0) return error("macro host auto-build enabled, but repo root could not be inferred (set HXHX_REPO_ROOT)");

				try {
					final entrypoints = anyNonBuiltinMacro(parsed.macros) ? parsed.macros : new Array<String>();
					final exe = buildMacroHostExe(repoRoot, macroHostClassPaths, entrypoints);
					Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);
				} catch (e:Dynamic) {
					return error("macro host auto-build failed: " + Std.string(e));
				}
			}

			hxhx.macro.MacroState.reset();
			hxhx.macro.MacroState.seedFromCliDefines(parsed.defines);
			hxhx.macro.MacroState.setGeneratedHxDir(haxe.io.Path.join([outAbs, "_gen_hx"]));

				// Stage 4 bring-up slice: support CLI `--macro` by routing expressions to the macro host.
				//
				// This does not yet allow macros to transform the typed AST (e.g. `@:build`). It is purely
				// “execute macro expressions and surface deterministic results/errors”.
				try {
					macroSession = MacroHostClient.openSession();
					for (i in 0...parsed.macros.length) {
						Sys.println("macro_run[" + i + "]=" + macroSession.run(parsed.macros[i]));
					}
				} catch (e:Dynamic) {
					closeMacroSession();
					return error("macro failed: " + Std.string(e));
				}

			// Bring-up diagnostics: dump HXHX_* defines set by macros so tests can assert macro effects.
			for (name in hxhx.macro.MacroState.listDefineNames()) {
				if (StringTools.startsWith(name, "HXHX_")) {
					Sys.println("macro_define[" + name + "]=" + hxhx.macro.MacroState.definedValue(name));
				}
			}
		}

		final classPaths = {
			final base = parsed.classPaths.map(cp -> absFromCwd(cwd, cp));
			final libs = new Array<String>();
			for (lib in parsed.libs) for (p in resolveHaxelibPaths(lib)) libs.push(absFromCwd(cwd, p));
			final extra = hxhx.macro.MacroState.listClassPaths().map(cp -> absFromCwd(cwd, cp));
			final out = base.concat(libs).concat(extra);
			if (hxhx.macro.MacroState.hasGeneratedHxModules()) {
				out.push(hxhx.macro.MacroState.getGeneratedHxDir());
			}
				out;
			}

		final resolved = try ResolverStage.parseProject(classPaths, parsed.main) catch (e:Dynamic) {
				closeMacroSession();
				return error("resolve failed: " + formatException(e));
			}
		if (resolved.length == 0) return error("resolver returned an empty module graph");
		Sys.println("resolved_modules=" + resolved.length);

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
			for (m in resolved) {
				try {
					final pm = ResolvedModule.getParsed(m);
					if (HxModuleDecl.getHeaderOnly(pm.getDecl())) {
						Sys.println("header_only_file[" + headerOnlyCount + "]=" + ResolvedModule.getFilePath(m));
						headerOnlyCount += 1;
					}
					parsedMethodsTotal += HxClassDecl.getFunctions(HxModuleDecl.getMainClass(pm.getDecl())).length;
					TyperStage.typeModule(pm);
					typedCount += 1;
				} catch (e:Dynamic) {
					closeMacroSession();
					return error(
						"type failed: " + ResolvedModule.getFilePath(m) + ": " + formatException(e)
					);
				}
			}

			if (macroSession != null) {
				final hooks = hxhx.macro.MacroState.listAfterTypingHookIds();
				for (i in 0...hooks.length) {
					try {
						macroSession.runHook("afterTyping", hooks[i]);
					} catch (e:Dynamic) {
						closeMacroSession();
						return error("afterTyping hook failed: " + Std.string(e));
					}
					Sys.println("hook_afterTyping[" + i + "]=ok");
				}
			}

			if (macroSession != null) {
				final hooks = hxhx.macro.MacroState.listOnGenerateHookIds();
				for (i in 0...hooks.length) {
					try {
						macroSession.runHook("onGenerate", hooks[i]);
					} catch (e:Dynamic) {
						closeMacroSession();
						return error("onGenerate hook failed: " + Std.string(e));
					}
					Sys.println("hook_onGenerate[" + i + "]=ok");
				}
			}

			closeMacroSession();
			Sys.println("typed_modules=" + typedCount);
			Sys.println("header_only_modules=" + headerOnlyCount);
			Sys.println("parsed_methods_total=" + parsedMethodsTotal);
			Sys.println("stage3=type_only_ok");
			return 0;
		}

		// Stage3 "real compiler" rung: type the full resolved graph (best-effort),
		// then emit/build an executable from the typed program.
		final typedModules = new Array<TypedModule>();
		for (m in resolved) {
			final pm = ResolvedModule.getParsed(m);
			typedModules.push(TyperStage.typeModule(pm));
		}

		if (macroSession != null) {
			final hooks = hxhx.macro.MacroState.listAfterTypingHookIds();
			for (i in 0...hooks.length) {
				try {
					macroSession.runHook("afterTyping", hooks[i]);
				} catch (e:Dynamic) {
					closeMacroSession();
					return error("afterTyping hook failed: " + Std.string(e));
				}
				Sys.println("hook_afterTyping[" + i + "]=ok");
			}
		}

		if (macroSession != null) {
			final hooks = hxhx.macro.MacroState.listOnGenerateHookIds();
			for (i in 0...hooks.length) {
				try {
					macroSession.runHook("onGenerate", hooks[i]);
				} catch (e:Dynamic) {
					closeMacroSession();
					return error("onGenerate hook failed: " + Std.string(e));
				}
				Sys.println("hook_onGenerate[" + i + "]=ok");
			}
		}

		// Collect generated modules after hooks.
		final generated = new Array<MacroExpandedModule.GeneratedOcamlModule>();
		for (name in hxhx.macro.MacroState.listOcamlModuleNames()) {
			generated.push({ name: name, source: hxhx.macro.MacroState.getOcamlModuleSource(name) });
		}
		final expanded = MacroStage.expandProgram(typedModules, generated);

		// Bring-up diagnostics: dump HXHX_* defines again after hooks.
		for (name in hxhx.macro.MacroState.listDefineNames()) {
			if (StringTools.startsWith(name, "HXHX_")) {
				Sys.println("macro_define2[" + name + "]=" + hxhx.macro.MacroState.definedValue(name));
			}
		}

		final exe = try EmitterStage.emitToDir(expanded, outAbs) catch (e:Dynamic) {
			closeMacroSession();
			return error("emit failed: " + Std.string(e));
		}

		Sys.println("stage3=ok");
		Sys.println("outDir=" + outAbs);
		Sys.println("exe=" + exe);

		closeMacroSession();

		final code = Sys.command(exe, []);
		if (code != 0) return error("built executable failed with exit code " + code);
		Sys.println("run=ok");
		return 0;
	}
}
