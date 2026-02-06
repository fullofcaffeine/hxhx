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

			try {
				// Special-case structured errors we throw from the bootstrap pipeline.
				// On the OCaml target, `Std.string(object)` can degrade to `<object>`,
				// so we format these explicitly.
				if (Std.isOfType(e, TyperError)) {
					final te:TyperError = cast e;
					// Use accessors to avoid OCaml `-opaque` record-label issues.
					final p = te.getPos();
					final line = p == null ? 0 : p.getLine();
					final col = p == null ? 0 : p.getColumn();
					return te.getFilePath() + ":" + line + ":" + col + ": " + te.getMessage();
				}

				final msg = Std.string(e);
				final debug = Sys.getEnv("HXHX_DEBUG_EXN");
				if (debug == "1" || debug == "true" || debug == "yes") {
					// Avoid `haxe.CallStack` on OCaml (it can create dune dependency cycles).
					var details = "typeof=" + Std.string(Type.typeof(e));
					final cls = Type.getClass(e);
					if (cls != null) details += ";class=" + Type.getClassName(cls);
					final fields = Reflect.fields(e);
					if (fields != null && fields.length > 0) details += ";fields=" + fields.join(",");
					if (Reflect.hasField(e, "message")) details += ";message=" + Std.string(Reflect.field(e, "message"));
					return msg + " :: " + details;
				}
				return msg;
			} catch (_:Dynamic) {
				return Std.string(e);
			}
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

	/**
		Stage4 bring-up: detect `@:build(...)` / `@:autoBuild(...)` metadata expressions in a source file.

		Why
		- Our bootstrap parser currently tolerates metadata by skipping tokens until it sees `class`,
		  but it does not store metadata in the AST yet.
		- For the first `@:build` rung, we only need the raw expression text to call into the macro host.

		What
		- Scans tokens until the first `class` keyword.
		- Extracts the text between the parentheses of `@:build(<expr>)` and `@:autoBuild(<expr>)`.

		Gotchas
		- This is intentionally conservative: it expects parentheses-delimited metadata and does not
		  attempt to understand complex expressions.
	**/
	static function findBuildMacroExprs(source:String):Array<String> {
		final out = new Array<String>();
		if (source == null || source.length == 0) return out;

		final lex = new HxLexer(source);
		var t = lex.next();

		while (true) {
			switch (t.kind) {
				case TEof:
					return out;
				case TKeyword(KClass):
					return out;
				case TOther(code) if (code == "@".code):
					final t2 = lex.next();
					final t3 = lex.next();
					final t4 = lex.next();

					final isMeta = switch ([t2.kind, t3.kind, t4.kind]) {
						case [TColon, TIdent("build"), TLParen]: true;
						case [TColon, TIdent("autoBuild"), TLParen]: true;
						case _: false;
					}
					if (!isMeta) {
						t = lex.next();
						continue;
					}

					// Capture raw text between balanced parens.
					final startIndex = t4.pos.getIndex() + 1; // after '('
					var depth = 1;
					var endIndex = startIndex;
					var inner = lex.next();
					while (true) {
						switch (inner.kind) {
							case TEof:
								endIndex = source.length;
								break;
							case TLParen:
								depth += 1;
							case TRParen:
								depth -= 1;
								if (depth == 0) {
									endIndex = inner.pos.getIndex(); // start of ')'
									break;
								}
							case _:
						}
						inner = lex.next();
					}

					final expr = trim(source.substring(startIndex, endIndex));
					if (expr.length > 0) out.push(expr);

					// Continue scanning after the closing ')'.
					t = lex.next();
					continue;
				case _:
			}

			t = lex.next();
		}

		return out;
	}

	static function parseGeneratedMembers(members:Array<String>):{functions:Array<HxFunctionDecl>, fields:Array<HxFieldDecl>} {
		if (members == null || members.length == 0) return { functions: [], fields: [] };
		final combined = members.join("\n");
		final fake = "class __HxHxBuildFields {\n" + combined + "\n}\n";
		final p = new HxParser(fake);
		final decl = p.parseModule();
		final cls = HxModuleDecl.getMainClass(decl);
		return {
			functions: HxClassDecl.getFunctions(cls),
			fields: HxClassDecl.getFields(cls)
		};
	}

		public static function run(args:Array<String>):Int {
			// Extract stage3-only flags before passing the remainder to `Stage1Args`.
			var outDir = "";
			var typeOnly = false;
			var emitFullBodies = false;
			var noEmit = false;
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
					case "--hxhx-no-emit":
						// Diagnostic rung: execute macros + type the module graph, but skip OCaml emission/build.
						noEmit = true;
						i += 1;
					case "--hxhx-emit-full-bodies":
						// Bring-up rung: emit best-effort OCaml for full statement bodies (not just first return).
						emitFullBodies = true;
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

		// Type-only mode is intended to answer “how far does the typer get?” without requiring a
		// working macro host. Upstream-ish workloads (e.g. `tests/unit/compile-macro.hxml`) often
		// include `--macro` directives which are essential for *real* compilation, but are not
		// necessary to diagnose missing parser/typer coverage.
		//
		// We therefore skip macros entirely when `--hxhx-type-only` is enabled.
		//
		// Note: This is a bring-up behavior. The Gate1 “non-delegating” acceptance run will
		// require real macro execution; type-only is only for diagnostics.
		if (typeOnly && parsed.macros.length > 0) {
			for (i in 0...parsed.macros.length) {
				Sys.println("macro_skipped[" + i + "]=" + parsed.macros[i]);
			}
		}

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

			// Macro state exists even in non-macro runs; it is a no-op unless the macro host calls back.
			hxhx.macro.MacroState.reset();
			hxhx.macro.MacroState.seedFromCliDefines(parsed.defines);
			hxhx.macro.MacroState.setGeneratedHxDir(haxe.io.Path.join([outAbs, "_gen_hx"]));

			final macroHostClassPaths = {
				final base = parsed.classPaths.map(cp -> absFromCwd(cwd, cp));
				final libs = new Array<String>();
				for (lib in parsed.libs) for (p in resolveHaxelibPaths(lib)) libs.push(absFromCwd(cwd, p));
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
						if (Path.normalize(cp) != stdAbs) filtered.push(cp);
					}
					filtered;
				} else {
					outAll;
				}
			}

		if (!typeOnly && parsed.macros.length > 0) {
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

		final roots = [parsed.main].concat(hxhx.macro.MacroState.listIncludedModules());
		final resolved = try ResolverStage.parseProjectRoots(classPaths, roots) catch (e:Dynamic) {
				closeMacroSession();
				return error("resolve failed: " + formatException(e));
			}
		if (resolved.length == 0) return error("resolver returned an empty module graph");
		Sys.println("resolved_modules=" + resolved.length);

		// Stage4 bring-up: apply `@:build(...)` macros by asking the macro host to emit raw
		// member snippets (reverse RPC) that we merge into the parsed module surface before typing.
		//
		// This is a small rung that does *not* implement upstream macro semantics yet.
		var anyBuildMacros = false;
		final buildExprsAll = new Array<String>();
		for (m in resolved) {
			final pm = ResolvedModule.getParsed(m);
			final exprs = findBuildMacroExprs(pm.getSource());
			if (exprs.length > 0) {
				anyBuildMacros = true;
				for (e in exprs) buildExprsAll.push(e);
			}
		}

		var resolvedForTyping = resolved;
		if (!typeOnly && anyBuildMacros) {
			// Ensure we have a macro host session.
			if (macroSession == null) {
				// Optional convenience: auto-build a macro host that contains the build macro entrypoints.
				if (MacroHostClient.resolveMacroHostExePath().length == 0 && shouldAutoBuildMacroHost()) {
					final repoRoot = inferRepoRootForScripts();
					if (repoRoot.length == 0) return error("macro host auto-build enabled, but repo root could not be inferred (set HXHX_REPO_ROOT)");
					try {
						final entrypoints = new Array<String>();
						for (e in buildExprsAll) if (!isBuiltinMacroExpr(e) && entrypoints.indexOf(e) == -1) entrypoints.push(e);
						final exe = buildMacroHostExe(repoRoot, macroHostClassPaths, entrypoints);
						Sys.putEnv("HXHX_MACRO_HOST_EXE", exe);
					} catch (e:Dynamic) {
						return error("macro host auto-build failed (build macros): " + Std.string(e));
					}
				}

				try {
					macroSession = MacroHostClient.openSession();
				} catch (e:Dynamic) {
					closeMacroSession();
					return error("macro host required for @:build, but could not be started: " + Std.string(e));
				}
			}

			final out2 = new Array<ResolvedModule>();
			for (m in resolved) {
				final pm = ResolvedModule.getParsed(m);
				final exprs = findBuildMacroExprs(pm.getSource());
				if (exprs.length == 0) {
					out2.push(m);
					continue;
				}

				final modulePath = ResolvedModule.getModulePath(m);
				// Reset any previously-emitted fields for this module for deterministic behavior.
				hxhx.macro.MacroState.clearBuildFields(modulePath);
				hxhx.macro.MacroState.setDefine("HXHX_BUILD_MODULE", modulePath);
				hxhx.macro.MacroState.setDefine("HXHX_BUILD_FILE", ResolvedModule.getFilePath(m));

				for (i in 0...exprs.length) {
					final expr = exprs[i];
					Sys.println("build_macro[" + modulePath + "][" + i + "]=" + expr);
					try {
						// The macro effect is communicated via reverse RPC `compiler.emitBuildFields`.
						Sys.println("build_macro_run[" + modulePath + "][" + i + "]=" + macroSession.run(expr));
					} catch (e:Dynamic) {
						closeMacroSession();
						return error("build macro failed: " + modulePath + ": " + Std.string(e));
					}
				}

				final snippets = hxhx.macro.MacroState.listBuildFields(modulePath);
				Sys.println("build_fields[" + modulePath + "]=" + snippets.length);
				if (snippets.length == 0) {
					out2.push(m);
					continue;
				}

				final gen = try parseGeneratedMembers(snippets) catch (e:Dynamic) {
					closeMacroSession();
					return error("build fields parse failed: " + modulePath + ": " + Std.string(e));
				}

				final oldDecl = pm.getDecl();
				final oldCls = HxModuleDecl.getMainClass(oldDecl);
				final mergedFns = HxClassDecl.getFunctions(oldCls).concat(gen.functions);
				final mergedFields = HxClassDecl.getFields(oldCls).concat(gen.fields);
				final newCls = new HxClassDecl(
					HxClassDecl.getName(oldCls),
					HxClassDecl.getHasStaticMain(oldCls),
					mergedFns,
					mergedFields
				);
				final newDecl = new HxModuleDecl(
					HxModuleDecl.getPackagePath(oldDecl),
					HxModuleDecl.getImports(oldDecl),
					newCls,
					HxModuleDecl.getHeaderOnly(oldDecl),
					HxModuleDecl.getHasToplevelMain(oldDecl)
				);
				final newParsed = new ParsedModule(pm.getSource(), newDecl, pm.getFilePath());
				out2.push(new ResolvedModule(modulePath, ResolvedModule.getFilePath(m), newParsed));
			}
			resolvedForTyping = out2;
		} else if (typeOnly && anyBuildMacros) {
			// Diagnostic mode: surface build macro expressions, but do not attempt to execute them.
			var i = 0;
			for (m in resolved) {
				final pm = ResolvedModule.getParsed(m);
				final exprs = findBuildMacroExprs(pm.getSource());
				for (e in exprs) {
					Sys.println("build_macro_skipped[" + i + "]=" + ResolvedModule.getModulePath(m) + ":" + e);
					i += 1;
				}
			}
		}

		final typerIndex = TyperIndex.build(resolvedForTyping);

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
			final rootFilePath = ResolvedModule.getFilePath(resolved[0]);
			var rootTyped:Null<TypedModule> = null;
			for (m in resolvedForTyping) {
				try {
					final pm = ResolvedModule.getParsed(m);
					if (HxModuleDecl.getHeaderOnly(pm.getDecl())) {
						Sys.println("header_only_file[" + headerOnlyCount + "]=" + ResolvedModule.getFilePath(m));
						headerOnlyCount += 1;
					}
					parsedMethodsTotal += HxClassDecl.getFunctions(HxModuleDecl.getMainClass(pm.getDecl())).length;
					final typed = TyperStage.typeResolvedModule(m, typerIndex);
					if (ResolvedModule.getFilePath(m) == rootFilePath) rootTyped = typed;
					typedCount += 1;
				} catch (e:Dynamic) {
					closeMacroSession();
					return error(
						"type failed: " + ResolvedModule.getFilePath(m) + ": " + formatException(e)
					);
				}
			}

			// Deterministic typer summary for the root module (bring-up diagnostics).
			if (rootTyped != null) {
				final fns = rootTyped.getEnv().getMainClass().getFunctions();
				for (i in 0...fns.length) {
					final tf = fns[i];
					final locals = tf.getLocals();
					final localsParts = new Array<String>();
					for (l in locals) localsParts.push(l.getName() + ":" + l.getType().toString());
					final params = tf.getParams();
					final paramParts = new Array<String>();
					for (p in params) paramParts.push(p.getName() + ":" + p.getType().toString());
					Sys.println(
						"typed_fn[" + i + "]="
						+ tf.getName()
						+ " args=" + paramParts.join(",")
						+ " locals=" + localsParts.join(",")
						+ " ret=" + tf.getReturnType().toString()
						+ " inferred=" + tf.getReturnExprType().toString()
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
		for (m in resolvedForTyping) {
			typedModules.push(TyperStage.typeResolvedModule(m, typerIndex));
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

			// Diagnostic rung: stop after macros + typing so we can iterate Stage4 macro model and Stage3 typer
			// coverage without being blocked by the bootstrap emitter/codegen.
			if (noEmit) {
				closeMacroSession();
				Sys.println("typed_modules=" + typedModules.length);
				Sys.println("stage3=no_emit_ok");
				return 0;
			}

			final exe = try EmitterStage.emitToDir(expanded, outAbs, emitFullBodies) catch (e:Dynamic) {
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
