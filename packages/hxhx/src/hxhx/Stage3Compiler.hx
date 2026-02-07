package hxhx;

import haxe.io.Path;
import haxe.io.Eof;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroHostClient.MacroHostSession;

private typedef HaxelibSpec = {
	/**
		Directories that should be added to the Haxe classpath.

		Notes
		- `haxelib path <lib>` historically prints these as raw lines (without a `-cp` prefix).
		- Some libraries also emit explicit `-cp` lines via `extraParams.hxml`. We normalize those
		  into this array as well.
	**/
	final classPaths:Array<String>;

	/**
		Raw `-D` defines from the library.

		Why keep them raw
		- Our conditional compilation + macro-state define seeding already expects the upstream-ish
		  `"name=value"` shape used by CLI `-D`.
	**/
	final defines:Array<String>;

	/**
		Raw `--macro <expr>` entries from the library.

		Important bring-up note
		- Stage3 currently treats `--library` primarily as classpath + define resolution.
		- Executing library-provided `--macro` initializers is intentionally **opt-in** via
		  `HXHX_RUN_HAXELIB_MACROS=1` to keep bring-up deterministic (and to avoid failing whenever
		  a library's macros aren't compiled into the current macro host).
	**/
	final macros:Array<String>;

	/** Any other flags printed by `haxelib path` that we don't recognize yet. **/
	final unknownArgs:Array<String>;
};

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

	static function escapeOneLine(s:String):String {
		if (s == null) return "";
		// Keep logs parseable and stable even when we store raw source snippets.
		//
		// Note: avoid repeated local rebinding (`out = replace(out, ...)`) here. During
		// Stage3 bring-up, `hxhx` is compiled by our OCaml backend, and conservative
		// codegen can drop intermediate assignment values.
		return StringTools.replace(
			StringTools.replace(
				StringTools.replace(
					StringTools.replace(s, "\\", "\\\\"),
					"\r",
					"\\r"
				),
				"\n",
				"\\n"
			),
			"\t",
			"\\t"
		);
	}

	static function countUnsupportedExprsInExpr(e:Null<HxExpr>):Int {
		if (e == null) return 0;
		return switch (e) {
			case EUnsupported(_): 1;
			case EField(obj, _): countUnsupportedExprsInExpr(obj);
				case ECall(callee, args):
					var c = countUnsupportedExprsInExpr(callee);
					for (a in args) c += countUnsupportedExprsInExpr(a);
					c;
				case ELambda(_args, body):
					countUnsupportedExprsInExpr(body);
				case ENew(_typePath, args):
					var c = 0;
					for (a in args) c += countUnsupportedExprsInExpr(a);
					c;
			case EUnop(_op, expr): countUnsupportedExprsInExpr(expr);
			case EBinop(_op, left, right): countUnsupportedExprsInExpr(left) + countUnsupportedExprsInExpr(right);
			case ETernary(cond, thenExpr, elseExpr):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInExpr(thenExpr) + countUnsupportedExprsInExpr(elseExpr);
			case EAnon(_names, values):
				var c = 0;
				for (v in values) c += countUnsupportedExprsInExpr(v);
				c;
			case EArrayDecl(values):
				var c = 0;
				for (v in values) c += countUnsupportedExprsInExpr(v);
				c;
			case EArrayAccess(arr, idx):
				countUnsupportedExprsInExpr(arr) + countUnsupportedExprsInExpr(idx);
			case ECast(expr, _hint):
				countUnsupportedExprsInExpr(expr);
			case EUntyped(expr):
				countUnsupportedExprsInExpr(expr);
			case _:
				0;
		}
	}

	static function collectUnsupportedExprRawInExpr(e:Null<HxExpr>, out:Array<String>, max:Int):Void {
		if (e == null) return;
		if (out.length >= max) return;
		switch (e) {
			case EUnsupported(raw):
				if (out.length < max) out.push(raw);
			case EField(obj, _):
				collectUnsupportedExprRawInExpr(obj, out, max);
				case ECall(callee, args):
					collectUnsupportedExprRawInExpr(callee, out, max);
					for (a in args) collectUnsupportedExprRawInExpr(a, out, max);
				case ELambda(_args, body):
					collectUnsupportedExprRawInExpr(body, out, max);
				case ENew(_typePath, args):
					for (a in args) collectUnsupportedExprRawInExpr(a, out, max);
				case EUnop(_op, expr):
					collectUnsupportedExprRawInExpr(expr, out, max);
			case EBinop(_op, left, right):
				collectUnsupportedExprRawInExpr(left, out, max);
				collectUnsupportedExprRawInExpr(right, out, max);
			case ETernary(cond, thenExpr, elseExpr):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInExpr(thenExpr, out, max);
				collectUnsupportedExprRawInExpr(elseExpr, out, max);
			case EAnon(_names, values):
				for (v in values) collectUnsupportedExprRawInExpr(v, out, max);
			case EArrayDecl(values):
				for (v in values) collectUnsupportedExprRawInExpr(v, out, max);
			case EArrayAccess(arr, idx):
				collectUnsupportedExprRawInExpr(arr, out, max);
				collectUnsupportedExprRawInExpr(idx, out, max);
			case ECast(expr, _hint):
				collectUnsupportedExprRawInExpr(expr, out, max);
			case EUntyped(expr):
				collectUnsupportedExprRawInExpr(expr, out, max);
			case _:
		}
	}

	static function collectUnsupportedExprRawInStmt(s:HxStmt, out:Array<String>, max:Int):Void {
		if (out.length >= max) return;
		switch (s) {
			case SBlock(stmts, _pos):
				for (ss in stmts) collectUnsupportedExprRawInStmt(ss, out, max);
			case SVar(_name, _hint, init, _pos):
				collectUnsupportedExprRawInExpr(init, out, max);
			case SIf(cond, thenBranch, elseBranch, _pos):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInStmt(thenBranch, out, max);
				if (elseBranch != null) collectUnsupportedExprRawInStmt(elseBranch, out, max);
			case SReturnVoid(_pos):
			case SReturn(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
			case SExpr(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
		}
	}

	static function collectUnsupportedExprRawInModule(pm:ParsedModule, max:Int):Array<String> {
		final decl = pm.getDecl();
		final cls = HxModuleDecl.getMainClass(decl);
		final out = new Array<String>();
		for (f in HxClassDecl.getFields(cls)) collectUnsupportedExprRawInExpr(HxFieldDecl.getInit(f), out, max);
		for (fn in HxClassDecl.getFunctions(cls)) {
			for (s in HxFunctionDecl.getBody(fn)) collectUnsupportedExprRawInStmt(s, out, max);
		}
		return out;
	}

	static function countUnsupportedExprsInStmt(s:HxStmt):Int {
		return switch (s) {
			case SBlock(stmts, _pos):
				var c = 0;
				for (ss in stmts) c += countUnsupportedExprsInStmt(ss);
				c;
			case SVar(_name, _hint, init, _pos):
				countUnsupportedExprsInExpr(init);
			case SIf(cond, thenBranch, elseBranch, _pos):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInStmt(thenBranch) + (elseBranch == null ? 0 : countUnsupportedExprsInStmt(elseBranch));
			case SReturnVoid(_pos):
				0;
			case SReturn(expr, _pos):
				countUnsupportedExprsInExpr(expr);
			case SExpr(expr, _pos):
				countUnsupportedExprsInExpr(expr);
		}
	}

	static function countUnsupportedExprsInModule(pm:ParsedModule):Int {
		final decl = pm.getDecl();
		final cls = HxModuleDecl.getMainClass(decl);
		var c = 0;
		for (f in HxClassDecl.getFields(cls)) c += countUnsupportedExprsInExpr(HxFieldDecl.getInit(f));
		for (fn in HxClassDecl.getFunctions(cls)) {
			for (s in HxFunctionDecl.getBody(fn)) c += countUnsupportedExprsInStmt(s);
		}
		return c;
	}

	static function countUnsupportedExprsInFunction(fn:HxFunctionDecl):Int {
		var c = 0;
		for (s in HxFunctionDecl.getBody(fn)) c += countUnsupportedExprsInStmt(s);
		return c;
	}

	static function bool01(v:Bool):String return v ? "1" : "0";
	static function isTrueEnv(name:String):Bool {
		final v = trim(Sys.getEnv(name));
		return v == "1" || v == "true" || v == "yes";
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

	static function resolveHaxelibSpec(lib:String, cwd:String, seen:Map<String, Bool>, depth:Int):HaxelibSpec {
		if (depth > 25) {
			return throw "haxelib resolution depth exceeded while resolving: " + lib;
		}
		if (seen.exists(lib)) {
			// Dependency cycles can exist in dev setups; treat them as already-merged.
			return { classPaths: [], defines: [], macros: [], unknownArgs: [] };
		}
		seen.set(lib, true);

		final hxmlPath = findHaxeLibrariesHxml(lib, cwd);
		if (hxmlPath.length > 0) {
			return resolveHaxelibSpecFromHxml(hxmlPath, cwd, seen, depth);
		}

		return resolveHaxelibSpecViaProcess(lib);
	}

	static function resolveHaxelibSpecViaProcess(lib:String):HaxelibSpec {
		final classPaths = new Array<String>();
		final defines = new Array<String>();
		final macros = new Array<String>();
		final unknownArgs = new Array<String>();
		final p = new sys.io.Process(haxelibBin(), ["path", lib]);

		try {
			while (true) {
				final raw = p.stdout.readLine();
				final line = StringTools.trim(raw);
				if (line.length == 0) continue;
				if (!StringTools.startsWith(line, "-")) {
					classPaths.push(line);
					continue;
				}

				// `haxelib path` prints a 1-arg-per-line stream that may include `-D`, `--macro`, and
				// other compiler flags from `extraParams.hxml`.
				if (StringTools.startsWith(line, "-D ")) {
					final def = StringTools.trim(line.substr(3));
					if (def.length > 0) defines.push(def);
					continue;
				}
				if (StringTools.startsWith(line, "--macro ")) {
					final expr = StringTools.trim(line.substr(8));
					if (expr.length > 0) macros.push(expr);
					continue;
				}
				if (StringTools.startsWith(line, "-cp ")) {
					final cp = StringTools.trim(line.substr(4));
					if (cp.length > 0) classPaths.push(cp);
					continue;
				}
				if (StringTools.startsWith(line, "--class-path ")) {
					final cp = StringTools.trim(line.substr(13));
					if (cp.length > 0) classPaths.push(cp);
					continue;
				}

				unknownArgs.push(line);
			}
		} catch (_:Eof) {}

		final code = p.exitCode();
		if (code != 0) {
			return throw "haxelib path " + lib + " failed with exit code " + code;
		}
		return { classPaths: classPaths, defines: defines, macros: macros, unknownArgs: unknownArgs };
	}

	static function resolveHaxelibSpecFromHxml(hxmlPath:String, cwd:String, seen:Map<String, Bool>, depth:Int):HaxelibSpec {
		final args = Hxml.parseFile(hxmlPath);
		if (args == null) return throw "failed to parse haxelib hxml: " + hxmlPath;

		final classPaths = new Array<String>();
		final defines = new Array<String>();
		final macros = new Array<String>();
		final unknownArgs = new Array<String>();

		inline function pushUnique(a:Array<String>, v:String):Void {
			if (v == null || v.length == 0) return;
			if (a.indexOf(v) == -1) a.push(v);
		}

		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "-cp" | "-p" | "--class-path":
					if (i + 1 < args.length) pushUnique(classPaths, args[i + 1]);
					i += 2;
				case "-D":
					if (i + 1 < args.length) pushUnique(defines, args[i + 1]);
					i += 2;
				case "--macro":
					if (i + 1 < args.length) pushUnique(macros, args[i + 1]);
					i += 2;
				case "-lib" | "--library":
					if (i + 1 >= args.length) return throw "malformed haxelib hxml (missing value after " + a + "): " + hxmlPath;
					final dep = args[i + 1];
					final depSpec = resolveHaxelibSpec(dep, cwd, seen, depth + 1);
					for (cp in depSpec.classPaths) pushUnique(classPaths, cp);
					for (d in depSpec.defines) pushUnique(defines, d);
					for (m in depSpec.macros) pushUnique(macros, m);
					for (u in depSpec.unknownArgs) pushUnique(unknownArgs, u);
					i += 2;
				case _:
					// Keep unknown flags so bring-up runners can introspect what's left to implement.
					if (a != null && a.length > 0 && StringTools.startsWith(a, "-")) pushUnique(unknownArgs, a);
					i += 1;
			}
		}

		return { classPaths: classPaths, defines: defines, macros: macros, unknownArgs: unknownArgs };
	}

	static function findHaxeLibrariesHxml(lib:String, cwd:String):String {
		// Lix-managed projects store resolved haxelib specs under `haxe_libraries/<lib>.hxml`.
		//
		// Why do this first
		// - In a lix repo, `haxelib path <lib>` may be a wrapper that fails unless the `.hxml`
		//   file exists. Parsing the `.hxml` directly keeps Stage3 non-delegating and avoids
		//   toolchain variance.
		var dir = (cwd == null || cwd.length == 0) ? "." : cwd;
		for (_ in 0...10) {
			final candidate = Path.normalize(Path.join([dir, "haxe_libraries", lib + ".hxml"]));
			if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate)) return candidate;
			final parent = Path.normalize(Path.join([dir, ".."]));
			if (parent == dir) break;
			dir = parent;
		}
		return "";
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

	static function parseDelimitedList(raw:String):Array<String> {
		final out = new Array<String>();
		if (raw == null) return out;
		final s = StringTools.trim(raw);
		if (s.length == 0) return out;

		// Accept either ';' or ',' as separators (bring-up convenience).
		final parts = s.indexOf(";") != -1 ? s.split(";") : s.split(",");
		for (p in parts) {
			if (p == null) continue;
			final t = StringTools.trim(p);
			if (t.length == 0) continue;
			if (out.indexOf(t) == -1) out.push(t);
		}
		return out;
	}

		static function isBuiltinMacroExpr(expr:String):Bool {
			final e = trim(expr);
			// Builtins compiled into the macro host binary (and/or treated as "no-op builtins" during bring-up).
			//
			// Why
			// - Stage4 brings up a *safe* macro execution surface incrementally. Many upstream macro expressions
			//   (especially in compiler test suites) are not supported as real "user macro entrypoints" yet.
			// - Auto-building a macro host that tries to execute those expressions can crash the host (because
			//   the runtime macro API surface is still incomplete).
			//
			// What
			// - Treat a tiny allowlist as builtins so they are NOT included in the auto-built macro-host entrypoint list.
			// - The expressions are still sent to the macro host via `macro.run`; the host may treat them as a no-op.
			return StringTools.startsWith(e, "BuiltinMacros.")
				|| StringTools.startsWith(e, "hxhxmacrohost.BuiltinMacros.")
				|| StringTools.startsWith(e, "hxhxmacrohost.BuiltinMacros")
				// Upstream null-safety test suite macros (Gate2 diagnostics).
				|| StringTools.startsWith(e, "nullSafety(")
				|| StringTools.startsWith(e, "Validator.register(");
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

	static function buildFieldsPayloadForParsed(pm:ParsedModule):String {
		final decl = pm.getDecl();
		final cls = HxModuleDecl.getMainClass(decl);
		final items = new Array<Dynamic>();

		for (fn in HxClassDecl.getFunctions(cls)) {
			items.push({
				name: HxFunctionDecl.getName(fn),
				kind: "fun",
				isStatic: HxFunctionDecl.getIsStatic(fn),
				visibility: Std.string(HxFunctionDecl.getVisibility(fn)),
			});
		}
		for (f in HxClassDecl.getFields(cls)) {
			items.push({
				name: HxFieldDecl.getName(f),
				kind: "var",
				isStatic: HxFieldDecl.getIsStatic(f),
				visibility: Std.string(HxFieldDecl.getVisibility(f)),
			});
		}

		// Encode as a length-prefixed fragment list so the macro host can parse it with `Protocol.kvParse`.
		final parts = new Array<String>();
		parts.push(hxhx.macro.MacroProtocol.encodeLen("c", Std.string(items.length)));
		for (i in 0...items.length) {
			final it = items[i];
			parts.push(hxhx.macro.MacroProtocol.encodeLen("n" + i, Std.string(Reflect.field(it, "name"))));
			parts.push(hxhx.macro.MacroProtocol.encodeLen("k" + i, Std.string(Reflect.field(it, "kind"))));
			parts.push(hxhx.macro.MacroProtocol.encodeLen("s" + i, (Reflect.field(it, "isStatic") == true) ? "1" : "0"));
			parts.push(hxhx.macro.MacroProtocol.encodeLen("v" + i, Std.string(Reflect.field(it, "visibility"))));
		}
		return parts.join(" ");
	}

		public static function run(args:Array<String>):Int {
			// Extract stage3-only flags before passing the remainder to `Stage1Args`.
			var outDir = "";
			var typeOnly = false;
			var emitFullBodies = false;
			var noEmit = false;
			var noRun = false;
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
					case "--hxhx-no-run":
						// Build-only rung: emit+build the OCaml executable, but do not execute it.
						//
						// Why
						// - Some compiler-shaped artifacts are *servers* (macro host, display server, etc.) and would
						//   block forever if we tried to run them as a validation step.
						// - Gate runners and scripts sometimes need an executable path, not its output.
						//
						// What
						// - We still type the full graph and produce `out.exe`, printing `exe=...` like normal.
						// - We print `run=skipped` instead of `run=ok`.
						noRun = true;
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

			function inferMainFromMacroExpr(expr:String):String {
				if (expr == null) return "";
				var s = StringTools.trim(expr);
				if (s.length == 0) return "";
				final p = s.indexOf("(");
				if (p != -1) s = StringTools.trim(s.substr(0, p));
				final lastDot = s.lastIndexOf(".");
				if (lastDot == -1) return s;
				return StringTools.trim(s.substr(0, lastDot));
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
			if (parsed.main != null && parsed.main.length > 0) {
				roots0.push(parsed.main);
			} else if (parsed.roots != null && parsed.roots.length > 0) {
				for (r in parsed.roots) if (r != null && r.length > 0) roots0.push(r);
			} else if (parsed.macros.length > 0) {
				final inferred = inferMainFromMacroExpr(parsed.macros[0]);
				if (inferred.length == 0) return error("missing -main <TypeName>");
				roots0.push(inferred);
			} else {
				return error("missing -main <TypeName>");
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
		if (typeOnly && parsed.macros.length > 0) {
			for (i in 0...parsed.macros.length) {
				Sys.println("macro_skipped[" + i + "]=" + parsed.macros[i]);
			}
		}

		// Stage4 bring-up: expression macro allowlist.
		//
		// These are call sites in *normal code* (not CLI `--macro`) that we will attempt to expand
		// before typing by asking the macro host for a replacement expression snippet.
		final exprMacros = parseDelimitedList(Sys.getEnv("HXHX_EXPR_MACROS"));

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
			final libsResolved = {
				final seen = new Map<String, Bool>();
				final out = new Array<HaxelibSpec>();
				for (lib in parsed.libs) out.push(resolveHaxelibSpec(lib, cwd, seen, 0));
				out;
			}
			final libDefines = {
				final out = new Array<String>();
				for (s in libsResolved) for (d in s.defines) if (out.indexOf(d) == -1) out.push(d);
				out;
			}
			final allDefines = parsed.defines.concat(libDefines);
			hxhx.macro.MacroState.seedFromCliDefines(allDefines);
			hxhx.macro.MacroState.setGeneratedHxDir(haxe.io.Path.join([outAbs, "_gen_hx"]));

			final libMacros = {
				final out = new Array<String>();
				for (s in libsResolved) for (m in s.macros) if (out.indexOf(m) == -1) out.push(m);
				out;
			}
			final runHaxelibMacros = isTrueEnv("HXHX_RUN_HAXELIB_MACROS");

			final macroHostClassPaths = {
				final base = parsed.classPaths.map(cp -> absFromCwd(cwd, cp));
				final libs = new Array<String>();
				for (s in libsResolved) for (p in s.classPaths) libs.push(absFromCwd(cwd, p));
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

		if (!typeOnly && (parsed.macros.length > 0 || exprMacros.length > 0 || (runHaxelibMacros && libMacros.length > 0))) {
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
			if (MacroHostClient.resolveMacroHostExePath().length == 0 && shouldAutoBuildMacroHost()) {
				final repoRoot = inferRepoRootForScripts();
				if (repoRoot.length == 0) return error("macro host auto-build enabled, but repo root could not be inferred (set HXHX_REPO_ROOT)");

				try {
					final entrypoints = new Array<String>();
					// Library-provided macros (from `haxelib path <lib>` output) when enabled.
					if (runHaxelibMacros) {
						for (e in libMacros) if (!isBuiltinMacroExpr(e) && entrypoints.indexOf(e) == -1) entrypoints.push(e);
					}
					// CLI macros: include only non-builtin expressions (builtins are already compiled into the host).
					if (anyNonBuiltinMacro(parsed.macros)) {
						for (e in parsed.macros) if (!isBuiltinMacroExpr(e) && entrypoints.indexOf(e) == -1) entrypoints.push(e);
					}
					// Expression macros: always include (they are not builtins by default).
					for (e in exprMacros) if (entrypoints.indexOf(e) == -1) entrypoints.push(e);
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
					if (runHaxelibMacros) {
						for (i in 0...libMacros.length) Sys.println("lib_macro_run[" + i + "]=" + macroSession.run(libMacros[i]));
					}
					for (i in 0...parsed.macros.length) Sys.println("macro_run[" + i + "]=" + macroSession.run(parsed.macros[i]));
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
			for (s in libsResolved) for (p in s.classPaths) libs.push(absFromCwd(cwd, p));
			final extra = hxhx.macro.MacroState.listClassPaths().map(cp -> absFromCwd(cwd, cp));
			final out = base.concat(libs).concat(extra);
			if (hxhx.macro.MacroState.hasGeneratedHxModules()) {
				out.push(hxhx.macro.MacroState.getGeneratedHxDir());
			}
				out;
			}

		// Defines available for conditional compilation filtering.
		//
		// Notes
		// - CLI `-D` defines were seeded into MacroState at the start of the run.
		// - Macro-time `Compiler.define(...)` calls (reverse RPC) also populate MacroState.
		// - ResolverStage will use this map to strip inactive `#if` branches before parsing.
		final definesMap = HxDefineMap.fromRawDefines(allDefines);
		definesMap.set("sys", "1");
		definesMap.set("ocaml", "1");
		for (n in hxhx.macro.MacroState.listDefineNames()) {
			definesMap.set(n, hxhx.macro.MacroState.definedValue(n));
		}

		final roots = roots0.concat(hxhx.macro.MacroState.listIncludedModules());
		final resolved = try ResolverStage.parseProjectRoots(classPaths, roots, definesMap) catch (e:Dynamic) {
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
				hxhx.macro.MacroState.setBuildFieldsPayload(buildFieldsPayloadForParsed(pm));

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
				for (fn in gen.functions) genFnKeys.set(fnKey(fn), true);
				final genFieldKeys:Map<String, Bool> = new Map();
				for (f in gen.fields) genFieldKeys.set(fieldKey(f), true);

				final keptFns = new Array<HxFunctionDecl>();
				for (fn in HxClassDecl.getFunctions(oldCls)) {
					if (!genFnKeys.exists(fnKey(fn))) keptFns.push(fn);
				}
				final mergedFns = keptFns.concat(gen.functions);

				final keptFields = new Array<HxFieldDecl>();
				for (f in HxClassDecl.getFields(oldCls)) {
					if (!genFieldKeys.exists(fieldKey(f))) keptFields.push(f);
				}
				final mergedFields = keptFields.concat(gen.fields);
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

		// Stage4 bring-up: expression macro expansion pass (pre-typing).
		//
		// This is a small rung that only expands allowlisted exact call strings, and only supports
		// a tiny returned expression subset (parsed by `HxParser.parseExprText`).
		if (!typeOnly && exprMacros.length > 0) {
			if (macroSession == null) {
				closeMacroSession();
				return error("expression macro expansion requested (HXHX_EXPR_MACROS), but no macro host session is available");
			}
			final exp = ExprMacroExpander.expandResolvedModules(resolvedForTyping, macroSession, exprMacros);
			resolvedForTyping = exp.modules;
			Sys.println("expr_macros_expanded=" + exp.expandedCount);
		}

		final typerIndex = TyperIndex.build(resolvedForTyping);
		final moduleLoader = new ModuleLoader(classPaths, definesMap, typerIndex);
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
						Sys.println(
							"unsupported_file[" + unsupportedFilesCount + "]="
							+ ResolvedModule.getFilePath(m)
							+ " header_only=" + bool01(HxModuleDecl.getHeaderOnly(pm.getDecl()))
							+ " unsupported_exprs=" + unsupportedInFile
						);
						if (traceUnsupported) {
							// Per-function summary so unsupported shapes are actionable even when raw payloads
							// come from native protocol rungs (which may not preserve source locations yet).
							final cls = HxModuleDecl.getMainClass(pm.getDecl());
							for (fn in HxClassDecl.getFunctions(cls)) {
								final fnUnsupported = countUnsupportedExprsInFunction(fn);
								if (fnUnsupported <= 0) continue;
								Sys.println(
									"unsupported_fn[" + unsupportedFnCount + "]="
									+ ResolvedModule.getFilePath(m)
									+ ":" + HxFunctionDecl.getName(fn)
									+ " unsupported_exprs=" + fnUnsupported
								);
								unsupportedFnCount += 1;
								if (unsupportedFnCount >= 50) break;
							}
							for (raw in collectUnsupportedExprRawInModule(pm, 20)) {
								final escaped = escapeOneLine(raw);
								Sys.println(
									"unsupported_expr[" + unsupportedRawCount + "]="
									+ ResolvedModule.getFilePath(m)
									+ ":raw=" + escaped
									+ " len=" + (raw == null ? 0 : raw.length)
								);
								unsupportedRawCount += 1;
								if (unsupportedRawCount >= 50) break;
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
					if (ResolvedModule.getFilePath(m) == rootFilePath) rootTyped = typed;
					typedCount += 1;
				} catch (e:Dynamic) {
					closeMacroSession();
					return error(
						"type failed: " + ResolvedModule.getFilePath(m) + ": " + formatException(e)
					);
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

			if (macroSession != null) {
				final hooks = hxhx.macro.MacroState.listAfterGenerateHookIds();
				for (i in 0...hooks.length) {
					try {
						macroSession.runHook("afterGenerate", hooks[i]);
					} catch (e:Dynamic) {
						closeMacroSession();
						return error("afterGenerate hook failed: " + Std.string(e));
					}
					Sys.println("hook_afterGenerate[" + i + "]=ok");
				}
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
		final typedModules = new Array<TypedModule>();
		// Worklist so the typer can lazily load modules on demand. Newly loaded modules are typed and
		// included in the emitted program so `dune build` does not fail on missing modules.
		final toType = resolvedForTyping.copy();
		var cursor = 0;
		while (cursor < toType.length) {
			final m = toType[cursor];
			cursor += 1;
			try {
				typedModules.push(TyperStage.typeResolvedModule(m, typerIndex, moduleLoader));
			} catch (e:Dynamic) {
				closeMacroSession();
				return error("type failed: " + ResolvedModule.getFilePath(m) + ": " + formatException(e));
			}
			for (nm in moduleLoader.drainNewModules()) {
				resolvedForTyping.push(nm);
				toType.push(nm);
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

		if (macroSession != null) {
			final hooks = hxhx.macro.MacroState.listAfterGenerateHookIds();
			for (i in 0...hooks.length) {
				try {
					macroSession.runHook("afterGenerate", hooks[i]);
				} catch (e:Dynamic) {
					closeMacroSession();
					return error("afterGenerate hook failed: " + Std.string(e));
				}
				Sys.println("hook_afterGenerate[" + i + "]=ok");
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
				var headerOnlyCount = 0;
				var unsupportedExprsTotal = 0;
				var unsupportedFilesCount = 0;
				final traceUnsupported = isTrueEnv("HXHX_TRACE_UNSUPPORTED");
				var unsupportedRawCount = 0;
				var unsupportedFnCount = 0;
				var unsupportedFileIndex = 0;
				for (m in resolvedForTyping) {
					final pm = ResolvedModule.getParsed(m);
					if (HxModuleDecl.getHeaderOnly(pm.getDecl())) headerOnlyCount += 1;
					final unsupportedInFile = countUnsupportedExprsInModule(pm);
					unsupportedExprsTotal += unsupportedInFile;
					if (unsupportedInFile > 0) {
						unsupportedFilesCount += 1;
						Sys.println(
							"unsupported_file[" + unsupportedFileIndex + "]="
							+ ResolvedModule.getFilePath(m)
							+ " header_only=" + bool01(HxModuleDecl.getHeaderOnly(pm.getDecl()))
							+ " unsupported_exprs=" + unsupportedInFile
						);
						unsupportedFileIndex += 1;
						if (traceUnsupported) {
							final cls = HxModuleDecl.getMainClass(pm.getDecl());
							for (fn in HxClassDecl.getFunctions(cls)) {
								final fnUnsupported = countUnsupportedExprsInFunction(fn);
								if (fnUnsupported <= 0) continue;
								Sys.println(
									"unsupported_fn[" + unsupportedFnCount + "]="
									+ ResolvedModule.getFilePath(m)
									+ ":" + HxFunctionDecl.getName(fn)
									+ " unsupported_exprs=" + fnUnsupported
								);
								unsupportedFnCount += 1;
								if (unsupportedFnCount >= 50) break;
							}
							for (raw in collectUnsupportedExprRawInModule(pm, 20)) {
								final escaped = escapeOneLine(raw);
								Sys.println(
									"unsupported_expr[" + unsupportedRawCount + "]="
									+ ResolvedModule.getFilePath(m)
									+ ":raw=" + escaped
									+ " len=" + (raw == null ? 0 : raw.length)
								);
								unsupportedRawCount += 1;
								if (unsupportedRawCount >= 50) break;
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

			final exe = try EmitterStage.emitToDir(expanded, outAbs, emitFullBodies) catch (e:Dynamic) {
				closeMacroSession();
				return error("emit failed: " + Std.string(e));
			}

		Sys.println("stage3=ok");
		Sys.println("outDir=" + outAbs);
		Sys.println("exe=" + exe);

		closeMacroSession();

		if (noRun) {
			Sys.println("run=skipped");
			return 0;
		}

		final code = Sys.command(exe, []);
		if (code != 0) return error("built executable failed with exit code " + code);
		Sys.println("run=ok");
		return 0;
	}
}
