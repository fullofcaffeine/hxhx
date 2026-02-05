package hxhx;

import haxe.io.Path;
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

	static function absFromCwd(cwd:String, path:String):String {
		if (path == null || path.length == 0) return cwd;
		return Path.isAbsolute(path) ? Path.normalize(path) : Path.normalize(Path.join([cwd, path]));
	}

	public static function run(args:Array<String>):Int {
		// Extract stage3-only flags before passing the remainder to `Stage1Args`.
		var outDir = "";
		final rest = new Array<String>();
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "--hxhx-out":
					if (i + 1 >= args.length) return error("missing value after --hxhx-out");
					outDir = args[i + 1];
					i += 2;
				case _:
					rest.push(a);
					i += 1;
			}
		}

		final parsed = Stage1Args.parse(rest);
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

			if (parsed.macros.length > 0) {
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
			final extra = hxhx.macro.MacroState.listClassPaths().map(cp -> absFromCwd(cwd, cp));
			final out = base.concat(extra);
			if (hxhx.macro.MacroState.hasGeneratedHxModules()) {
				out.push(hxhx.macro.MacroState.getGeneratedHxDir());
			}
				out;
			}

			final resolved = try ResolverStage.parseProject(classPaths, parsed.main) catch (e:Dynamic) {
				closeMacroSession();
				return error("resolve failed: " + Std.string(e));
			}
		if (resolved.length == 0) return error("resolver returned an empty module graph");

		final root:ResolvedModule = resolved[0];
		final ast = ResolvedModule.getParsed(root);

		final typed = TyperStage.typeModule(ast);

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
		final expanded = MacroStage.expand(typed, generated);

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
