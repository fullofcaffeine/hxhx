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

	static function escapeOcamlIdentPart(s:String):String {
		if (s == null || s.length == 0) return "_";
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
			// Stage 3 bring-up: enough structure for `haxe.Int64` callsites that destructure
			// into `{ low, high }` (common in stdlib and upstream unit tests).
			case "haxe.Int64", "Int64": "HxInt64.t";
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

	static function exprToOcamlString(e:HxExpr, ?tyByIdent:Map<String, TyType>):String {
		return switch (e) {
			case EString(v): escapeOcamlString(v);
			case EInt(v): "string_of_int " + Std.string(v);
			case EBool(v): "string_of_bool " + (v ? "true" : "false");
			case EFloat(v): "string_of_float " + Std.string(v);
			case EIdent(name)
				if (tyByIdent != null
					&& tyByIdent.exists(name)
					&& tyByIdent.get(name) != null
					&& tyByIdent.get(name).toString() == "Int"):
				"string_of_int " + ocamlValueIdent(name);
			case EIdent(name)
				if (tyByIdent != null
					&& tyByIdent.exists(name)
					&& tyByIdent.get(name) != null
					&& tyByIdent.get(name).toString() == "Float"):
				"string_of_float " + ocamlValueIdent(name);
			case EIdent(name)
				if (tyByIdent != null
					&& tyByIdent.exists(name)
					&& tyByIdent.get(name) != null
					&& tyByIdent.get(name).toString() == "Bool"):
				"string_of_bool " + ocamlValueIdent(name);
			case _: escapeOcamlString("<unsupported>");
		}
	}

	static function exprToOcaml(e:HxExpr, ?arityByIdent:Map<String, Int>, ?tyByIdent:Map<String, TyType>):String {
		inline function tyForIdent(name:String):String {
			if (tyByIdent == null) return "";
			if (!tyByIdent.exists(name)) return "";
			final t = tyByIdent.get(name);
			return t == null ? "" : t.toString();
		}

		function isFloatExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EFloat(_):
					true;
				case EIdent(name):
					tyForIdent(name) == "Float";
				case _:
					false;
			}
		}

		function isIntExpr(expr:HxExpr):Bool {
			return switch (expr) {
				case EInt(_):
					true;
				case EIdent(name):
					tyForIdent(name) == "Int";
				case _:
					false;
			}
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
				"(classify_float (" + exprToOcaml(arg, arityByIdent, tyByIdent) + ") = FP_nan)";
			case ECall(EField(EIdent("Math"), "isFinite"), [arg]):
				"(match classify_float (" + exprToOcaml(arg, arityByIdent, tyByIdent) + ") with | FP_nan | FP_infinite -> false | _ -> true)";
			case ECall(EField(EIdent("Math"), "isInfinite"), [arg]):
				"(classify_float (" + exprToOcaml(arg, arityByIdent, tyByIdent) + ") = FP_infinite)";
			case ECall(EField(EIdent("Math"), "abs"), [arg]):
				// Best-effort numeric abs. Prefer float when the expression looks float-typed.
				(isFloatExpr(arg) ? "abs_float " : (isIntExpr(arg) ? "abs " : "abs_float "))
				+ "(" + exprToOcaml(arg, arityByIdent, tyByIdent) + ")";
			case EField(EIdent("Math"), "NaN"):
				"nan";
			case EField(EIdent("Math"), "POSITIVE_INFINITY"):
				"infinity";
			case EField(EIdent("Math"), "NEGATIVE_INFINITY"):
				"neg_infinity";
			case EField(EIdent("Math"), "PI"):
				"(4.0 *. atan 1.0)";

			// Stage 3 "full body" rung: map common output calls to OCaml printing.
			//
			// This is *not* a real stdlib/runtime mapping; it's a bootstrap convenience so we can
			// observe that emitted function bodies are actually executing.
			case ECall(EIdent("trace"), [arg]):
				"print_endline (" + exprToOcamlString(arg, tyByIdent) + ")";
			case ECall(EField(EIdent("Sys"), "println"), [arg]):
				"print_endline (" + exprToOcamlString(arg, tyByIdent) + ")";

			case EBool(v): v ? "true" : "false";
			case EInt(v): Std.string(v);
			case EFloat(v): Std.string(v);
			case EString(v): escapeOcamlString(v);
			case EIdent(name): isUpperStart(name) ? name : ocamlValueIdent(name);
			case EThis:
				// Stage 3 bring-up: no object semantics yet.
				"(Obj.magic 0)";
			case ESuper:
				// Stage 3 bring-up: no class hierarchy semantics yet.
				"(Obj.magic 0)";
			case ENull:
				// Stage 3 bring-up: null semantics are not modeled yet. Keep compilation moving.
				"(Obj.magic 0)";
			case ENew(_typePath, _args):
				// Stage 3 bring-up: allocation + constructors are not modeled yet.
				"(Obj.magic 0)";
			case EField(obj, field):
				exprToOcaml(obj, arityByIdent, tyByIdent) + "." + ocamlValueIdent(field);
			case ECall(callee, args):
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
				final missing =
					switch (callee) {
						case EIdent(name) if (arityByIdent != null && arityByIdent.exists(name)):
							final expected = arityByIdent.get(name);
							(expected != null && expected > args.length) ? (expected - args.length) : 0;
						case EField(EThis, name) if (arityByIdent != null && arityByIdent.exists(name)):
							final expected = arityByIdent.get(name);
							(expected != null && expected > args.length) ? (expected - args.length) : 0;
						case _:
							0;
					}

				final c = exprToOcaml(callee, arityByIdent, tyByIdent);
				final fullArgs = args.copy();
				for (_ in 0...missing) fullArgs.push(ENull);

				if (fullArgs.length == 0) {
					c + " ()";
				} else {
					c + " " + fullArgs.map(a -> "(" + exprToOcaml(a, arityByIdent, tyByIdent) + ")").join(" ");
				}
			case EUnop(op, expr):
				// Stage 3 expansion: support a tiny subset of unary ops so simple control-flow
				// fixtures can become non-trivial.
				//
				// Non-goal: correct numeric tower (Int vs Float) or full operator set.
				// If we can't emit safely, fall back to bring-up poison.
				switch (op) {
					case "!":
						"(not (" + exprToOcaml(expr, arityByIdent, tyByIdent) + "))";
					case "-":
						"(-(" + exprToOcaml(expr, arityByIdent, tyByIdent) + "))";
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
				final la = exprToOcaml(a, arityByIdent, tyByIdent);
				final rb = exprToOcaml(b, arityByIdent, tyByIdent);
				switch (op) {
					case "+" | "-" | "*" | "/" | "%":
						// Best-effort numeric lowering:
						// - if both sides look like floats, use OCaml float operators,
						// - if both sides look like ints, use OCaml int operators,
						// - otherwise, collapse to bring-up poison to avoid type errors.
						final aIsF = isFloatExpr(a);
						final bIsF = isFloatExpr(b);
						final aIsI = isIntExpr(a);
						final bIsI = isIntExpr(b);
						if ((aIsF && bIsF) && (op == "+" || op == "-" || op == "*" || op == "/")) {
							final fop = switch (op) {
								case "+": "+.";
								case "-": "-.";
								case "*": "*.";
								case "/": "/.";
								case _: op;
							}
							"((" + la + ") " + fop + " (" + rb + "))";
						} else if ((aIsI && bIsI) || (!aIsF && !bIsF)) {
							"((" + la + ") " + op + " (" + rb + "))";
						} else {
							"(Obj.magic 0)";
						}
					case "==":
						"((" + la + ") = (" + rb + "))";
					case "!=":
						"((" + la + ") <> (" + rb + "))";
					case "<" | ">" | "<=" | ">=":
						"((" + la + ") " + op + " (" + rb + "))";
					case "&&" | "||":
						"((" + la + ") " + op + " (" + rb + "))";
					case _:
						"(Obj.magic 0)";
				}
			case EUnsupported(_):
				// Stage 3 bring-up: avoid aborting emission when partial parsing produces
				// unsupported nodes inside a larger expression tree. The goal here is to
				// progress to the next missing semantic, not to be correct yet.
				"(Obj.magic 0)";
		}
	}

	static function returnExprToOcaml(
		expr:HxExpr,
		allowedValueIdents:Map<String, Bool>,
		?arityByIdent:Map<String, Int>,
		?tyByIdent:Map<String, TyType>
	):String {
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
					true;
				case EThis:
					true;
				case ESuper:
					true;
				case ENew(_, _):
					true;
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
					//
					// Important: we still collapse assignment to bring-up poison (it frequently depends
					// on side effects + correct lvalue semantics which we don't model yet).
					switch (op) {
						case "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" | "+" | "-" | "*" | "/" | "%":
							hasBringupPoison(a) || hasBringupPoison(b);
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
					} else if (allowedValueIdents != null && allowedValueIdents.exists(name)) {
						false;
					} else {
						true;
					}
				case EField(obj, _):
					hasBringupPoison(obj);
				case ECall(callee, args):
					if (hasBringupPoison(callee)) return true;
					for (a in args) if (hasBringupPoison(a)) return true;
					false;
				case _:
					false;
			}
		}

			// If the expression tree contains unsupported/null nodes anywhere, don't attempt partial OCaml
			// emission: it tends to produce unbound identifiers (we are not modeling locals/blocks yet).
			// Collapse to the bootstrap escape hatch instead.
		if (hasBringupPoison(expr)) return "(Obj.magic 0)";

		return exprToOcaml(expr, arityByIdent, tyByIdent);
	}

	static function stmtListToOcaml(
		stmts:Array<HxStmt>,
		allowedValueIdents:Map<String, Bool>,
		returnExc:String,
		?arityByIdent:Map<String, Int>,
		?tyByIdent:Map<String, TyType>
	):String {
		if (stmts == null || stmts.length == 0) return "()";

		function condToOcamlBool(e:HxExpr):String {
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
					boolOrTrue(returnExprToOcaml(e, allowedValueIdents, arityByIdent, tyByIdent));
				case EBinop(op, _, _) if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||"):
					boolOrTrue(returnExprToOcaml(e, allowedValueIdents, arityByIdent, tyByIdent));
				case _:
					// Conservative default: we do not have real typing for conditions yet.
					// Keep bring-up resilient by treating unknown conditions as true.
					"true";
			};
		}

		function stmtToUnit(s:HxStmt):String {
			return switch (s) {
				case SBlock(ss, _pos):
					stmtListToOcaml(ss, allowedValueIdents, returnExc, arityByIdent, tyByIdent);
				case SVar(_name, _typeHint, _init, _pos):
					// Handled at the list level because it needs to wrap the remainder with `let ... in`.
					"()";
				case SIf(cond, thenBranch, elseBranch, _pos):
					final thenUnit = stmtToUnit(thenBranch);
					final elseUnit = elseBranch == null ? "()" : stmtToUnit(elseBranch);
					"if " + condToOcamlBool(cond) + " then (" + thenUnit + ") else (" + elseUnit + ")";
				case SReturnVoid(_pos):
					"raise (" + returnExc + " (Obj.repr ()))";
				case SReturn(expr, _pos):
					"raise (" + returnExc + " (Obj.repr (" + returnExprToOcaml(expr, allowedValueIdents, arityByIdent, tyByIdent) + ")))";
				case SExpr(expr, _pos):
					// Avoid emitting invalid OCaml when we parse Haxe assignment as `EBinop("=")`.
					switch (expr) {
						case EBinop("=", _l, _r):
							"()";
						case _:
							"ignore (" + returnExprToOcaml(expr, allowedValueIdents, arityByIdent, tyByIdent) + ")";
			}
		}
		}

		// Fold right so `var` statements can wrap the rest with `let name = init in ...`.
		var out = "()";
		for (i in 0...stmts.length) {
			final s = stmts[stmts.length - 1 - i];
			switch (s) {
				case SVar(name, _typeHint, init, _pos):
					final rhs = init == null ? "(Obj.magic 0)" : returnExprToOcaml(init, allowedValueIdents, arityByIdent, tyByIdent);
					out = "let " + ocamlValueIdent(name) + " = " + rhs + " in (" + out + ")";
				case _:
					out = "(" + stmtToUnit(s) + "; " + out + ")";
			}
		}
		return out;
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
	public static function emitToDir(p:MacroExpandedProgram, outDir:String, emitFullBodies:Bool = false):String {
		if (outDir == null || StringTools.trim(outDir).length == 0) throw "stage3 emitter: missing outDir";
		final outAbs = haxe.io.Path.normalize(outDir);
		if (!sys.FileSystem.exists(outAbs)) sys.FileSystem.createDirectory(outAbs);

		function ocamldepSort(mlFiles:Array<String>):Array<String> {
			if (mlFiles == null || mlFiles.length <= 1) return mlFiles;

			final ocamldep = {
				final v = Sys.getEnv("OCAMLDEP");
				(v == null || v.length == 0) ? "ocamldep" : v;
			}

			final p = new sys.io.Process(ocamldep, ["-sort"].concat(mlFiles));
			final chunks = new Array<String>();
			try {
				while (true) {
					chunks.push(p.stdout.readLine());
				}
			} catch (_:haxe.io.Eof) {}

			final code = p.exitCode();
			p.close();
			if (code != 0) throw "stage3 emitter: ocamldep -sort failed with exit code " + code;

			final sorted = new Array<String>();
			for (c in chunks) {
				for (t in c.split(" ")) {
					final s = StringTools.trim(t);
					if (s.length == 0) continue;
					if (!StringTools.endsWith(s, ".ml")) continue;
					sorted.push(s);
				}
			}

			// Best-effort: if ocamldep output looks empty or incomplete, fall back to caller order.
			if (sorted.length == 0) return mlFiles;
			return sorted;
		}

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
		{
			final shimName = "Std";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(
					shimPath,
					"(* hxhx(stage3) bootstrap shim: Std *)\n"
					+ "let isOfType _ _ = false\n"
					+ "let string _ = \"\"\n"
				);
				generatedPaths.push(shimName + ".ml");
			}
		}
		{
			final shimName = "Lambda";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(
					shimPath,
					"(* hxhx(stage3) bootstrap shim: Lambda *)\n"
					+ "let has _ _ = false\n"
					+ "let exists _ _ = false\n"
					+ "let iter _ _ = ()\n"
					+ "let count _ = 0\n"
				);
				generatedPaths.push(shimName + ".ml");
			}
		}
		{
			final shimName = "Reflect";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(
					shimPath,
					"(* hxhx(stage3) bootstrap shim: Reflect *)\n"
					+ "let field _ _ = (Obj.magic 0)\n"
					+ "let isFunction _ = false\n"
					+ "let compare _ _ = 0\n"
				);
				generatedPaths.push(shimName + ".ml");
			}
		}
		{
			final shimName = "HxPosInfos";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
					sys.io.File.saveContent(
						shimPath,
						"(* hxhx(stage3) bootstrap shim: haxe.PosInfos *)\n"
						+ "type t = {\n"
						+ "  fileName : string;\n"
						+ "  lineNumber : int;\n"
						+ "  className : string;\n"
						+ "  methodName : string;\n"
						+ "  customParams : Obj.t;\n"
						+ "}\n"
					);
					generatedPaths.push(shimName + ".ml");
				}
		}
		{
			final shimName = "HxInt64";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(
					shimPath,
					"(* hxhx(stage3) bootstrap shim: haxe.Int64 (shape-only) *)\n"
					+ "type t = {\n"
					+ "  low : int;\n"
					+ "  high : int;\n"
					+ "}\n"
				);
				generatedPaths.push(shimName + ".ml");
			}
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
			final arityByName:Map<String, Int> = new Map();
			for (tf in typedFns) arityByName.set(tf.getName(), tf.getParams().length);

			final out = new Array<String>();
			out.push("(* Generated by hxhx(stage3) bootstrap emitter *)");
			out.push("");

			var sawMain = false;
			final exceptions = new Array<String>();
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
						final allowed:Map<String, Bool> = new Map();
						final tyByIdent:Map<String, TyType> = new Map();
						for (a in args) allowed.set(a.getName(), true);
						for (a in args) tyByIdent.set(a.getName(), a.getType());
						// Allow calls between methods in the same emitted module.
					//
					// Why
					// - In Haxe, an unqualified call like `generated()` inside `Main.main` refers to a
					//   static method on the current class.
					// - In OCaml emission, those methods become top-level `let` bindings in the same
					//   compilation unit, so the call is safe and should not be treated as bring-up poison.
					for (tf2 in typedFns) allowed.set(tf2.getName(), true);
					// Only allow locals when we're actually emitting statement bodies that bind them.
					// In the "return-expression-only" rung, referencing locals would produce unbound
					// identifiers in OCaml, so we treat them as poison and collapse to `Obj.magic`.
						if (emitFullBodies) {
							for (l in tf.getLocals()) allowed.set(l.getName(), true);
							for (l in tf.getLocals()) tyByIdent.set(l.getName(), l.getType());
						}

				final body = if (parsedFn == null) {
					"()";
					} else if (!emitFullBodies) {
						returnExprToOcaml(parsedFn.getFirstReturnExpr(), allowed, arityByName, tyByIdent);
					} else {
					// OCaml exception constructors must start with an uppercase letter.
					final exc = "HxReturn_" + escapeOcamlIdentPart(nameRaw);
					exceptions.push("exception " + exc + " of Obj.t");
					final stmts = HxFunctionDecl.getBody(parsedFn);
					// Ensure the `try` expression itself typechecks as the function return type.
					//
					// Why
					// - In this bring-up emitter we implement `return` via exceptions.
					// - The typed OCaml expression in the `try` body must still have type `retTy`,
					//   even if the only "real" return path is the exception handler.
					//
					// How
					// - Append `(Obj.magic 0)` in the no-return path and cast the entire `try` to `retTy`.
					// - This is intentionally non-semantic but avoids OCaml type errors like:
					//   "This variant expression is expected to have type bool; There is no constructor () within type bool".
						"((" //
						+ "try (" + stmtListToOcaml(stmts, allowed, exc, arityByName, tyByIdent) + "; (Obj.magic 0)) "
						+ "with " + exc + " v -> (Obj.magic v)"
						+ ") : " + retTy + ")";
					};

				// Keep return type annotation to make early typing behavior visible.
				final kw = i == 0 ? "let rec" : "and";
				out.push(kw + " " + name + " " + ocamlArgs + " : " + retTy + " = " + body);
				out.push("");
			}

			if (emitFullBodies && exceptions.length > 0) {
				// Prepend exceptions so the `try ... with` clauses can reference them.
				out.insert(2, exceptions.join("\n") + "\n");
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

		// Compile in a dependency-respecting unit order.
		//
		// Why
		// - OCaml requires module providers to be compiled before their users.
		// - Our resolved module order is "Haxe-ish" and does not guarantee OCaml compilation order.
		//
		// How
		// - Use `ocamldep -sort` to topologically sort the emitted `.ml` units.
		// - Keep the root unit last so `let () = main ()` (when present) runs after linking deps.
		final orderedMl = ocamldepSort(generatedPaths.concat(emittedModulePaths));
		final orderedNoRoot = new Array<String>();
		final rootName = rootPath;
		for (f in orderedMl) if (rootName == null || f != rootName) orderedNoRoot.push(f);
		if (rootName != null) orderedNoRoot.push(rootName);

		final args = new Array<String>();
		args.push("-o");
		args.push("out.exe");
		for (p in orderedNoRoot) args.push(p);
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
