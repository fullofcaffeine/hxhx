/**
	Stage 2 codegen/emitter skeleton.

	Why:
	- The real Haxe compiler has multiple generators; for Haxe-in-Haxe we’ll need
	  at minimum a bytecode or OCaml-emission strategy for self-hosting.
	- Even before the full compiler exists, we want an end-to-end “typed → emitted →
	  built artifact” slice to keep bootstrapping honest.

	What (in this repo today):
	- `emit` remains a no-op placeholder for the long-term backend story.
	- `emitToDir` is a Stage 3 bring-up helper used by `hxhx --hxhx-stage3`:
	  it emits a *tiny* OCaml program for the supported bootstrap subset and
	  builds it with `ocamlopt`.

	Supported subset (intentionally narrow):
	- A single module with a single main class.
	- `static` functions whose body is effectively `return <literal-or-ident>;`
	  (or no explicit return, treated as `Void`).

	Non-goals:
	- Full Haxe semantics (nullability, classes, enums, etc.).
	- Runtime library integration (`hx_runtime`) — this helper emits OCaml that
	  depends only on the OCaml standard library.
**/
class EmitterStage {
	public static function emit(_:MacroExpandedModule):Void {
		// Stub: eventually write output files / bytecode.
	}

	static function ocamlTypeFromTy(t:TyType):String {
		return switch (t.toString()) {
			case "Int": "int";
			case "Float": "float";
			case "Bool": "bool";
			case "String": "string";
			case "Void": "unit";
			// Stage 3: anything else is unknown; avoid making up a type.
			case _: "_";
		}
	}

	static function lowerFirst(name:String):String {
		if (name == null || name.length == 0) return "_";
		final c = name.charCodeAt(0);
		final isUpper = c >= 65 && c <= 90;
		return isUpper ? (String.fromCharCode(c + 32) + name.substr(1)) : name;
	}

	static function isOcamlKeyword(name:String):Bool {
		if (name == null) return false;
		return switch (name) {
			case "and" | "as" | "assert" | "begin" | "class" | "constraint" | "do" | "done" | "downto" | "else"
				| "end" | "exception" | "external" | "false" | "for" | "fun" | "function" | "functor" | "if" | "in"
				| "include" | "inherit" | "initializer" | "lazy" | "let" | "match" | "method" | "module" | "mutable"
				| "new" | "nonrec" | "object" | "of" | "open" | "or" | "private" | "rec" | "sig" | "struct" | "then"
				| "to" | "true" | "try" | "type" | "val" | "virtual" | "when" | "while" | "with":
				true;
			case _:
				false;
		}
	}

	static function ocamlValueIdent(raw:String):String {
		final base = lowerFirst(raw);
		if (base == "_" || base.length == 0) return "_";
		return isOcamlKeyword(base) ? (base + "_") : base;
	}

	static function isUpperStart(name:String):Bool {
		if (name == null || name.length == 0) return false;
		final c = name.charCodeAt(0);
		return c >= 65 && c <= 90;
	}

	static function escapeOcamlString(s:String):String {
		if (s == null) return "\"\"";
		// Minimal escaping: enough for our fixtures.
		var out = s;
		out = StringTools.replace(out, "\\", "\\\\");
		out = StringTools.replace(out, "\"", "\\\"");
		out = StringTools.replace(out, "\n", "\\n");
		out = StringTools.replace(out, "\r", "\\r");
		out = StringTools.replace(out, "\t", "\\t");
		return "\"" + out + "\"";
	}

	static function exprToOcaml(e:HxExpr):String {
		return switch (e) {
			case EBool(v): v ? "true" : "false";
			case EInt(v): Std.string(v);
			case EFloat(v): Std.string(v);
			case EString(v): escapeOcamlString(v);
			case EIdent(name): isUpperStart(name) ? name : ocamlValueIdent(name);
			case ENull:
				throw "stage3 emitter: null literal emission is not implemented yet";
			case EField(obj, field):
				exprToOcaml(obj) + "." + ocamlValueIdent(field);
			case ECall(callee, args):
				final c = exprToOcaml(callee);
				if (args.length == 0) {
					c + " ()";
				} else {
					c + " " + args.map(a -> "(" + exprToOcaml(a) + ")").join(" ");
				}
			case EUnsupported(raw):
				throw "stage3 emitter: unsupported expression: " + raw;
		}
	}

	static function returnExprToOcaml(expr:HxExpr):String {
		// Stage 3 bring-up: if we couldn't parse/type an expression, keep compilation moving.
		//
		// `Obj.magic` is a deliberate bootstrap escape hatch:
		// - it typechecks against any return annotation, which helps us progress through
		//   upstream-shaped code without having to implement full typing/emission yet.
		// - it is *not* semantically correct; it is only for bring-up.
		return switch (expr) {
			case EUnsupported(_), ENull:
				"(Obj.magic 0)";
			case _:
				exprToOcaml(expr);
		}
	}

	/**
		Emit a minimal OCaml program for the typed module and build it as a native executable.

		Why
		- This is the smallest “compiler-shaped” slice we can validate early:
		  Stage 3 typing produces a stable environment, and we can prove it can
		  drive *some* codegen all the way to a runnable binary.

		What
		- Writes two files into `outDir`:
		  - `out.ml`: generated OCaml source
		  - `out.exe`: compiled executable (name chosen for CI simplicity)
		- Returns the path to `out.exe`.

		How
		- Extracts function signatures from the typed environment and return
		  expressions from the parsed AST (we only support simple return shapes).
		- Builds using `ocamlopt` (override via `OCAMLOPT` env var).
	**/
	public static function emitToDir(p:MacroExpandedProgram, outDir:String):String {
		if (outDir == null || StringTools.trim(outDir).length == 0) throw "stage3 emitter: missing outDir";
		final outAbs = haxe.io.Path.normalize(outDir);
		if (!sys.FileSystem.exists(outAbs)) sys.FileSystem.createDirectory(outAbs);

		// Stage 4 bring-up: emit macro-generated OCaml modules (if any).
		//
		// This is a minimal “generate code” effect: macros can request extra target compilation units
		// without us implementing full typed AST transforms yet.
		final generatedPaths = new Array<String>();
		for (gm in p.getGeneratedOcamlModules()) {
			if (gm == null) continue;
			final name = gm.name == null ? "" : StringTools.trim(gm.name);
			if (name.length == 0) continue;
			final path = haxe.io.Path.join([outAbs, name + ".ml"]);
			sys.io.File.saveContent(path, gm.source == null ? "" : gm.source);
			generatedPaths.push(name + ".ml");
		}

		final typedModules = p.getTypedModules();
		if (typedModules.length == 0) throw "stage3 emitter: empty typed module graph";

		function emitModule(tm:TypedModule, isRoot:Bool):Null<String> {
			final decl = tm.getParsed().getDecl();
			final mainClass = HxModuleDecl.getMainClass(decl);
			final className = HxClassDecl.getName(mainClass);
			if (className == null || className.length == 0 || className == "Unknown") return null;

			final parsedFns = HxClassDecl.getFunctions(mainClass);
			final parsedByName = new Map<String, HxFunctionDecl>();
			for (fn in parsedFns) parsedByName.set(HxFunctionDecl.getName(fn), fn);

			final typedFns = tm.getEnv().getMainClass().getFunctions();

			final out = new Array<String>();
			out.push("(* Generated by hxhx(stage3) bootstrap emitter *)");
			out.push("");

			var sawMain = false;
			for (i in 0...typedFns.length) {
				final tf = typedFns[i];
				final nameRaw = tf.getName();
				final name = ocamlValueIdent(nameRaw);
				if (name == "main") sawMain = true;

				final args = tf.getParams();
				final ocamlArgs = args.length == 0
					? "()"
					: args.map(a -> "(" + ocamlValueIdent(a.getName()) + " : " + ocamlTypeFromTy(a.getType()) + ")").join(" ");

				final parsedFn = parsedByName.get(nameRaw);
				final retTy = ocamlTypeFromTy(tf.getReturnType());
				final body = parsedFn == null ? "()" : returnExprToOcaml(parsedFn.getFirstReturnExpr());

				// Keep return type annotation to make early typing behavior visible.
				final kw = i == 0 ? "let rec" : "and";
				out.push(kw + " " + name + " " + ocamlArgs + " : " + retTy + " = " + body);
				out.push("");
			}

			if (isRoot && sawMain) {
				out.push("let () = ignore (main ())");
				out.push("");
			}

			final mlPath = haxe.io.Path.join([outAbs, className + ".ml"]);
			sys.io.File.saveContent(mlPath, out.join("\n"));
			return className + ".ml";
		}

		// Emit dependencies first, but link the root module last so its `let () = main ()`
		// runs after all referenced compilation units are linked.
		final emittedModulePaths = new Array<String>();
		final deps = typedModules.slice(1);
		for (tm in deps) {
			final path = emitModule(tm, false);
			if (path != null) emittedModulePaths.push(path);
		}
		final rootPath = emitModule(typedModules[0], true);
		if (rootPath != null) emittedModulePaths.push(rootPath);

		final exePath = haxe.io.Path.join([outAbs, "out.exe"]);
		try {
			if (sys.FileSystem.exists(exePath)) sys.FileSystem.deleteFile(exePath);
		} catch (_:Dynamic) {}

		final ocamlopt = {
			final v = Sys.getEnv("OCAMLOPT");
			(v == null || v.length == 0) ? "ocamlopt" : v;
		}

		// Compile from within `outAbs` so the compiler finds the `.cmi` it just produced.
		final prevCwd = try Sys.getCwd() catch (_:Dynamic) null;
		if (prevCwd == null) throw "stage3 emitter: cannot read current working directory";
		Sys.setCwd(outAbs);

		// Compile generated modules first, then typed module units (in dependency order).
		final args = new Array<String>();
		args.push("-o");
		args.push("out.exe");
		for (p in generatedPaths) args.push(p);
		for (p in emittedModulePaths) args.push(p);
		final code = try Sys.command(ocamlopt, args) catch (e:Dynamic) {
			Sys.setCwd(prevCwd);
			throw e;
		};
		Sys.setCwd(prevCwd);
		if (code != 0) throw "stage3 emitter: ocamlopt failed with exit code " + code;
		if (!sys.FileSystem.exists(exePath)) throw "stage3 emitter: missing built executable: " + exePath;
		return exePath;
	}
}
