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
			//
			// Note
			// - We intentionally name the shim module `Haxe_Int64` (not `HxInt64`) because:
			//   - Static calls like `haxe.Int64.make(...)` lower to the module name derived from the
			//     type path (`haxe.Int64` -> `Haxe_Int64`) in the Stage3 bootstrap emitter.
			//   - Keeping the type module name aligned avoids "Unbound module Haxe_Int64" failures
			//     when compiling stdlib code under the Stage3 emit runner.
			case "haxe.Int64", "Int64": "Haxe_Int64.t";
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

	static function upperFirst(s:String):String {
		if (s == null || s.length == 0) return s;
		final c = s.charCodeAt(0);
		final isLower = c >= 97 && c <= 122;
		return isLower ? (String.fromCharCode(c - 32) + s.substr(1)) : s;
	}

	static function ocamlModuleNameFromTypePathParts(parts:Array<String>):String {
		if (parts == null || parts.length == 0) return "Unknown";
		final escaped = parts.map(escapeOcamlIdentPart);
		escaped[0] = upperFirst(escaped[0]);
		return escaped.join("_");
	}

	static function ocamlModuleNameFromTypePath(typePath:String):String {
		if (typePath == null) return "Unknown";
		final trimmed = StringTools.trim(typePath);
		if (trimmed.length == 0) return "Unknown";
		return ocamlModuleNameFromTypePathParts(trimmed.split("."));
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

	static function escapeOcamlString(s:String):String {
		if (s == null) return "\"\"";
		// Minimal escaping: enough for our fixtures.
		//
		// Note (bootstrap/OCaml backend):
		// - Avoid re-assigning the same local repeatedly (`out = ...`) here.
		// - During Stage3 bring-up, `hxhx` itself is compiled by our OCaml backend, and a
		//   bug/limitation in local-rebinding codegen can cause `out = StringTools.replace(...)`
		//   to drop the new value (result is evaluated and ignored).
		// - Nesting calls keeps the semantics correct even under conservative codegen.
		final out =
			StringTools.replace(
				StringTools.replace(
					StringTools.replace(
						StringTools.replace(
							StringTools.replace(s, "\\", "\\\\"),
							"\"",
							"\\\""
						),
						"\n",
						"\\n"
					),
					"\r",
					"\\r"
				),
				"\t",
				"\\t"
			);
		return "\"" + out + "\"";
	}

	/**
		Best-effort constant folding for string expressions.

		Why
		- Stage 3 bring-up wants a tiny “escape hatch” for embedding raw OCaml expressions
		  via `untyped __ocaml__("<ocaml expr>")`.
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

	static function exprToOcamlString(e:HxExpr, ?tyByIdent:Map<String, TyType>):String {
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
				case EUnop("!", _),
					EBinop("==", _, _),
					EBinop("!=", _, _),
					EBinop("<", _, _),
					EBinop(">", _, _),
					EBinop("<=", _, _),
					EBinop(">=", _, _),
					EBinop("&&", _, _),
					EBinop("||", _, _):
					final s = exprToOcaml(cond, null, tyByIdent, null);
					s == "(Obj.magic 0)" ? "true" : s;
				case _:
					"true";
			};
		}

			return switch (e) {
				case EString(v): escapeOcamlString(v);
				case EEnumValue(name): escapeOcamlString(name);
			// When an expression is demanded as a string (e.g. trace/println), treat `+` as
			// string concatenation and lower it to OCaml's `^`.
			case EBinop("+", a, b):
				"(" + exprToOcamlString(a, tyByIdent) + " ^ " + exprToOcamlString(b, tyByIdent) + ")";
				case ECall(EField(EIdent("Std"), "string"), [arg]):
				// String interpolation lowering uses `Std.string(...)` to force stringification.
				//
				// Important
				// - Do not inline this as `exprToOcamlString(arg)`:
				//   - it would degrade complex values (arrays, tagged values) to `<unsupported>`,
				//   - and it would diverge from the target runtime’s own stringification behavior.
					"Std.string (Obj.repr (" + exprToOcaml(arg, null, tyByIdent, null, null, null) + "))";
				case ECall(EField(_obj, "join"), [_sep]):
					// Bring-up: join returns a string; delegate to normal expression lowering when available.
					exprToOcaml(e, null, tyByIdent, null, null, null);
				// Bootstrap: allow string-y ternaries in upstream-ish code (runci/System.hx).
				case ETernary(cond, thenExpr, elseExpr):
				"(if " + condToOcamlBoolForString(cond) + " then " + exprToOcamlString(thenExpr, tyByIdent) + " else " + exprToOcamlString(elseExpr, tyByIdent) + ")";
			case EInt(v): "string_of_int " + Std.string(v);
			case EBool(v): "string_of_bool " + (v ? "true" : "false");
			case EFloat(v): "string_of_float " + Std.string(v);
				case EIdent(name)
					if (tyByIdent != null
						&& tyByIdent.get(name) != null
						&& tyByIdent.get(name).toString() == "Int"):
					"string_of_int " + ocamlValueIdent(name);
				case EIdent(name)
					if (tyByIdent != null
						&& tyByIdent.get(name) != null
						&& tyByIdent.get(name).toString() == "Float"):
					"string_of_float " + ocamlValueIdent(name);
				case EIdent(name)
					if (tyByIdent != null
						&& tyByIdent.get(name) != null
						&& tyByIdent.get(name).toString() == "Bool"):
					"string_of_bool " + ocamlValueIdent(name);
				case EIdent(name)
					if (tyByIdent != null
						&& tyByIdent.get(name) != null
						&& tyByIdent.get(name).toString() == "String"):
					ocamlValueIdent(name);
				case EIdent(name)
					if (tyByIdent != null
						&& tyByIdent.get(name) != null
						&& StringTools.startsWith(tyByIdent.get(name).toString(), "Array<")):
					// Haxe string interpolation uses `Std.string(...)` for non-strings.
					// For `Array<String>`, upstream RunCi relies on `Array.toString()` semantics,
					// which are equivalent to `join(",")`.
					//
					// Using `Std.string` on our array representation would currently degrade to
					// "<object>" (because `dynamic_toStdString` can't reliably detect records).
					final t = tyByIdent.get(name).toString();
					final compact = StringTools.replace(t, " ", "");
					(compact.indexOf("Array<String>") == 0)
						? ("HxBootArray.join (" + ocamlValueIdent(name) + ") (\",\") (fun (s : string) -> s)")
						: ("Std.string (Obj.repr (" + ocamlValueIdent(name) + "))");
				case EIdent(name)
					if (tyByIdent != null
						&& tyByIdent.get(name) != null
						&& tyByIdent.get(name).toString() == "Array"):
					"Std.string (Obj.repr (" + ocamlValueIdent(name) + "))";
			case _:
				// Bring-up default: prefer *some* stringification over `<unsupported>` so
				// upstream harness logs remain readable (and don't change meaning).
				//
				// Note: this uses the backend's `Std.string` implementation (Haxe semantics),
				// not OCaml's `Stdlib.string_of_*`.
				"Std.string (Obj.repr (" + exprToOcaml(e, null, tyByIdent, null, null, null) + "))";
		}
	}

			static function exprToOcaml(
				e:HxExpr,
				?arityByIdent:Map<String, Int>,
				?tyByIdent:Map<String, TyType>,
				?staticImportByIdent:Map<String, String>,
				?currentPackagePath:String,
				?moduleNameByPkgAndClass:Map<String, String>
			):String {
				inline function tyForIdent(name:String):String {
					if (tyByIdent == null) return "";
					final t = tyByIdent.get(name);
					return t == null ? "" : t.toString();
				}

			function isFloatExpr(expr:HxExpr):Bool {
				return switch (expr) {
					case EFloat(_):
						true;
					case EIdent(name):
						tyForIdent(name) == "Float";
					case EBinop(op, a, b) if (op == "+" || op == "-" || op == "*" || op == "/"):
						// Best-effort: propagate float-ness through arithmetic.
						isFloatExpr(a) || isFloatExpr(b);
					case ETernary(_cond, thenExpr, elseExpr):
						isFloatExpr(thenExpr) && isFloatExpr(elseExpr);
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
					case EBinop(op, a, b) if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%"):
						// Best-effort: propagate int-ness through arithmetic when both sides look int-ish.
						isIntExpr(a) && isIntExpr(b);
					case ETernary(_cond, thenExpr, elseExpr):
						isIntExpr(thenExpr) && isIntExpr(elseExpr);
					case _:
						false;
				}
			}

			function isStringExpr(expr:HxExpr):Bool {
				return switch (expr) {
					case EString(_):
						true;
					case EIdent(name):
						tyForIdent(name) == "String";
					case EBinop("+", a, b):
						// String concatenation is represented as `+` in Haxe, but Stage3 typing info is often
						// incomplete for nested expressions. Recursing avoids emitting OCaml `+` between strings.
						isStringExpr(a) || isStringExpr(b);
					case ETernary(_cond, thenExpr, elseExpr):
						isStringExpr(thenExpr) && isStringExpr(elseExpr);
					case _:
						false;
				}
			}

				function isSysIoProcessExpr(expr:HxExpr):Bool {
					return switch (expr) {
						case EIdent(name):
							final t = tyForIdent(name);
							t == "sys.io.Process" || t == "sys.io.Process.Process";
						case ECast(inner, _hint):
							isSysIoProcessExpr(inner);
						case _:
							false;
					}
				}

				function extendTyByIdent(ty:Null<Map<String, TyType>>, name:String, t:TyType):Map<String, TyType> {
					final out = new Map<String, TyType>();
					if (ty != null) {
						for (k in ty.keys()) out.set(k, ty.get(k));
					}
					out.set(name, t);
					return out;
				}

				function extendTyByIdentMany(ty:Null<Map<String, TyType>>, names:Array<String>, t:TyType):Map<String, TyType> {
					final out = new Map<String, TyType>();
					if (ty != null) {
						for (k in ty.keys()) out.set(k, ty.get(k));
					}
					if (names != null) for (n in names) out.set(n, t);
					return out;
				}

				function exprToOcamlForConcat(expr:HxExpr):String {
					// Best-effort: keep concatenation type-safe by stringifying obvious primitives.
					// For complex expressions we assume the caller is already producing a string.
					return switch (expr) {
					case EInt(_), EFloat(_), EBool(_), EIdent(_):
						exprToOcamlString(expr, tyByIdent);
					case _:
						exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				}
			}

			function exprToOcamlAsFloatValue(expr:HxExpr):String {
				// Best-effort numeric coercion: promote obvious Ints to float.
				return switch (expr) {
					case EInt(v):
						"float_of_int " + Std.string(v);
					case EIdent(name) if (tyForIdent(name) == "Int"):
						"float_of_int " + ocamlValueIdent(name);
					case _:
						exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
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
				"(classify_float ("
				+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ") = FP_nan)";
				case ECall(EField(EIdent("Math"), "isFinite"), [arg]):
				"(match classify_float ("
				+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
				+ ") with | FP_nan | FP_infinite -> false | _ -> true)";
				case ECall(EField(EIdent("Math"), "isInfinite"), [arg]):
					"(classify_float ("
					+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") = FP_infinite)";
					case ECall(EField(EIdent("Math"), "abs"), [arg]):
						// Best-effort numeric abs. Prefer float when the expression looks float-typed.
						(isFloatExpr(arg) ? "abs_float " : (isIntExpr(arg) ? "abs " : "abs_float "))
						+ "("
						+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
						+ ")";
				case EField(EIdent("String"), "fromCharCode"):
					// Stage 3 bring-up: map Haxe `String.fromCharCode(int)` to an OCaml function value.
					// This is used in upstream-ish stdlib code as `var fcc = String.fromCharCode;`.
					"(fun i -> String.make 1 (Char.chr i))";
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
				case ECall(EField(EIdent("StringTools"), "fastCodeAt"), [s, idx]),
					ECall(EField(EIdent("StringTools"), "unsafeCodeAt"), [s, idx]):
					final s2 = exprToOcaml(s, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					final i2 = exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					"(let __s = (" + s2 + ") in "
					+ "let __i = (" + i2 + ") in "
					+ "if (__i < 0) || (__i >= String.length __s) then (-1) else (Char.code (String.get __s __i)))";

					case ECall(EField(EIdent("StringTools"), "replace"), [_s, _sub, _by]):
					// Bring-up: avoid needing a real `StringTools` implementation in the Stage3 emitter output.
					escapeOcamlString("");

				case ECall(EField(EIdent("Std"), "is"), [_v, _t]):
					// Bring-up: type tests require RTTI/runtime; keep compilation moving.
					"true";

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
					"print_endline (" + exprToOcamlString(arg, tyByIdent) + ")";
				case ECall(EField(EIdent("Sys"), "println"), [arg]):
					"print_endline (" + exprToOcamlString(arg, tyByIdent) + ")";
				case ECall(EField(EIdent("Sys"), "print"), [arg]):
					"print_string (" + exprToOcamlString(arg, tyByIdent) + ")";
					case ECall(EField(obj, "toString"), []) if (isStringExpr(obj)):
					// Bring-up: in Haxe, `String.toString()` is an identity; mapping this avoids
					// poisoning common patterns like `input.readAll().toString()`.
					exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);

				case EBool(v): v ? "true" : "false";
			case EInt(v): Std.string(v);
			case EFloat(v): Std.string(v);
			case EString(v): escapeOcamlString(v);
				case EIdent(name):
					if (tyByIdent != null && tyByIdent.get(name) != null) {
						// Bound identifier (parameter / local / bring-up-allowed static field).
						ocamlValueIdent(name);
					} else if (arityByIdent != null && arityByIdent.exists(name)) {
						// Static method call within the same generated module becomes a top-level OCaml binding.
						ocamlValueIdent(name);
					} else if (staticImportByIdent != null && staticImportByIdent.get(name) != null) {
						// Stage 3 bring-up: approximate `import Foo.Bar.*` (static wildcard imports).
						final moduleName = staticImportByIdent.get(name);
						moduleName + "." + ocamlValueIdent(name);
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
				// Stage 3 bring-up: no object semantics yet.
				"(Obj.magic 0)";
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
						(typePath == "Array" && args.length == 0)
							? "HxBootArray.create ()"
						:
						(typePath == "sys.io.Process" || typePath == "sys.io.Process.Process") && args.length == 2
							? ("HxBootProcess.run ("
								+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
								+ ") ("
								+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
								+ ")")
								// Stage 3 bring-up: allocation + constructors are not modeled yet.
								: "(Obj.magic 0)";
					case EArrayComprehension(name, iterable, yieldExpr):
						// Lower `[for (x in it) e]` to a small imperative builder.
						//
						// Note: for now we only support array/range iterables (matching bring-up needs).
						final out = "__arr_comp_out";
						final v = ocamlValueIdent(name);
						final ty2 = extendTyByIdent(tyByIdent, name, TyType.fromHintText("Dynamic"));
						final body = exprToOcaml(yieldExpr, arityByIdent, ty2, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						return switch (iterable) {
							case ERange(startExpr, endExpr):
								final start = exprToOcaml(startExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
								final end = exprToOcaml(endExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
								"(let " + out + " = HxBootArray.create () in "
								+ "let __start = (" + start + ") in "
								+ "let __end = (" + end + ") in "
								+ "(if (__end <= __start) then () else (for " + v + " = __start to (__end - 1) do ignore (HxBootArray.push " + out + " (" + body + ")) done)); "
								+ out
								+ ")";
							case _:
								final it = exprToOcaml(iterable, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
								"(let " + out + " = HxBootArray.create () in "
								+ "HxBootArray.iter (" + it + ") (fun " + v + " -> ignore (HxBootArray.push " + out + " (" + body + "))); "
								+ out
								+ ")";
						};
					case EField(obj, field):
					// Stage 3 bring-up: model a couple of common "instance field" shapes that appear in
					// orchestration code, without committing to a full object layout/runtime.
					//
					// - Array.length (via the bootstrap `HxBootArray` shim)
					// - String.length (OCaml primitive)
					if (field == "length") {
						final o = exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						if (isStringExpr(obj)) {
							return "String.length (" + o + ")";
						}
						switch (obj) {
							case EArrayDecl(_):
								return "HxBootArray.length (" + o + ")";
							case EIdent(name):
								final t = tyForIdent(name);
								if (StringTools.startsWith(t, "Array<")) return "HxBootArray.length (" + o + ")";
							case _:
						}
					}

					// Stage 3 bring-up: treat a few `sys.io.Process` fields as intrinsic accessors.
					if (field == "stdout" && isSysIoProcessExpr(obj)) {
						return "HxBootProcess.stdout (" + exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
					}
					if (field == "stderr" && isSysIoProcessExpr(obj)) {
						return "HxBootProcess.stderr (" + exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
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
					final parts = tryExtractTypePathPartsFromExpr(obj);
					if (parts != null && parts.length > 0 && isUpperStart(parts[parts.length - 1])) {
						var modName = ocamlModuleNameFromTypePathParts(parts);
						// If the type path is unqualified (`Util.foo()`), prefer resolving it within the
						// current package when we know a matching emitted module exists.
						//
						// Example:
						// - Haxe: `package demo; class A { static function f() Util.ping(); }`
						// - OCaml: `Demo_Util.ping ()` (not `Util.ping ()`)
						if (parts.length == 1 && currentPackagePath != null && currentPackagePath.length > 0 && moduleNameByPkgAndClass != null) {
							final key = currentPackagePath + ":" + parts[0];
							final local = moduleNameByPkgAndClass.get(key);
							if (local != null && local.length > 0) modName = local;
						}
						modName + "." + ocamlValueIdent(field);
					} else {
						"(Obj.magic 0)";
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
							case EField(obj, "toLowerCase") if (args.length == 0):
								return "HxString.toLowerCase ("
									+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ") ()";
								case EField(obj, "toUpperCase") if (args.length == 0):
								return "HxString.toUpperCase ("
									+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ") ()";
							case EField(obj, "trim") if (args.length == 0):
								return "String.trim ("
									+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ")";
							case EField(EIdent("StringTools"), "trim") if (args.length == 1):
								return "String.trim ("
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
							case EField(obj, "substring") if (args.length == 2):
								return "HxString.substring ("
									+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ") ("
									+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ") ("
									+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ")";
						case EField(EIdent("Sys"), "println") if (args.length == 1):
							return "print_endline (" + exprToOcamlString(args[0], tyByIdent) + ")";
					case EField(ECall(EField(EIdent("Sys"), "stdout"), []), "flush") if (args.length == 0):
						return "(flush stdout)";
					// Stage 3 bring-up: `Sys.command(cmd, ?args)` is used by upstream RunCi to execute
					// the `haxe` toolchain (and a few shell snippets like `export FOO=1 && ...`).
					//
					// We route through the stage3 bootstrap shim so Gate2 can run without relying on
					// an external runtime layer. The shim itself decides whether to use `/usr/bin/env`
					// or a shell (`/bin/sh -c`) based on whether `args` is empty and the command looks
					// like it contains shell operators.
					case EField(EIdent("Sys"), "command") if (args.length == 1):
						return "HxBootProcess.command ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") (HxBootArray.create ())";
					case EField(EIdent("Sys"), "command") if (args.length == 2):
						// `Sys.command(cmd, null)` occurs in upstream `runci.System.runSysTest`.
						// In our bring-up model, `null` lowers to the `HxRuntime.hx_null` sentinel, so coerce to an empty
						// `HxBootArray` at runtime to avoid segfaulting in the shim.
						final rawCmd = exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						final rawArgs = exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						return "(let __args = Obj.repr (" + rawArgs + ") in "
							+ "let __arr : string HxBootArray.t = if __args == HxRuntime.hx_null then HxBootArray.create () else (Obj.obj __args) in "
							+ "HxBootProcess.command (" + rawCmd + ") __arr)";
					// Stage 3 bring-up: basic env/CWD helpers used by upstream RunCi orchestration.
						case EField(EIdent("Sys"), "getEnv") if (args.length == 1):
							return "(match Stdlib.Sys.getenv_opt ("
								+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
								+ ") with | Some v -> v | None -> Std.hx_null_string)";
					case EField(EIdent("Sys"), "args") if (args.length == 0):
						// Haxe: Sys.args() excludes argv[0].
						return "(let __argv = Stdlib.Sys.argv in "
							+ "let __len = Array.length __argv in "
							+ "if __len <= 1 then HxBootArray.create () "
							+ "else HxBootArray.of_list (Array.to_list (Array.sub __argv 1 (__len - 1))))";
					case EField(EIdent("Sys"), "putEnv") if (args.length == 2):
						return "((Unix.putenv ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")); ())";
					case EField(EIdent("Sys"), "setCwd") if (args.length == 1):
						return "(Stdlib.Sys.chdir ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ "))";
					case EField(EIdent("Sys"), "getCwd") if (args.length == 0):
						return "(Stdlib.Sys.getcwd ())";
					case EField(EIdent("Sys"), "systemName") if (args.length == 0):
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
					case EField(proc, "exitCode") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.exitCode (" + exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
					// Bring-up: `sys.io.Process.close()` exists for resource cleanup; our shim is eager
					// and already waits + buffers outputs, so close is a no-op.
					case EField(proc, "close") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.close (" + exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
					// Bring-up: allow reading process output as a single string.
					case EField(EField(proc, "stdout"), "readAll") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stdoutReadAll (" + exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
					case EField(EField(proc, "stderr"), "readAll") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stderrReadAll (" + exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
					// Bring-up: allow line-wise reads used by upstream `runci.System.getHaxelibPath`.
					case EField(EField(proc, "stdout"), "readLine") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stdoutReadLine (" + exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
					case EField(EField(proc, "stderr"), "readLine") if (args.length == 0 && isSysIoProcessExpr(proc)):
						return "HxBootProcess.stderrReadLine (" + exprToOcaml(proc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
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
						case EField(obj, "push") if (args.length == 1):
						switch (obj) {
							case EArrayDecl(_):
								return "HxBootArray.push (" + exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ") ("
									+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ")";
							case EIdent(name):
								final t = tyForIdent(name);
								if (StringTools.startsWith(t, "Array<")) {
									return "HxBootArray.push (" + exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ") ("
										+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
										+ ")";
									}
								case _:
							}
						case EField(obj, "copy") if (args.length == 0):
							switch (obj) {
								case EArrayDecl(_):
									return "HxBootArray.copy (" + exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
								case EIdent(name):
									final t = tyForIdent(name);
									if (StringTools.startsWith(t, "Array<")) {
										return "HxBootArray.copy (" + exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")";
									}
								case _:
							}
						case EField(obj, "concat") if (args.length == 1):
							switch (obj) {
								case EArrayDecl(_):
									return "HxBootArray.concat ("
										+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
										+ ") ("
										+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
										+ ")";
								case EIdent(name):
									final t = tyForIdent(name);
									if (StringTools.startsWith(t, "Array<")) {
										return "HxBootArray.concat ("
											+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
											+ ") ("
											+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
											+ ")";
									}
								case _:
							}
						case EField(obj, "join") if (args.length == 1):
							switch (obj) {
								case EIdent(name):
									final t = tyForIdent(name);
									if (t == "Array<String>" || t == "Array< String >" || t.indexOf("Array<String>") == 0) {
										return "HxBootArray.join ("
											+ exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
											+ ") ("
											+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
											+ ") (fun (s : string) -> s)";
									}
								case _:
							}
						case _:
					}

				final c = exprToOcaml(callee, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				// Safety: if the callee is already "bring-up poison", do not apply arguments.
				//
				// Why
				// - Applying args to a non-function expression produces OCaml warnings/errors
				//   and can cascade into type mismatches.
				// - In bring-up we prefer collapsing to poison over producing invalid OCaml.
				if (c == "(Obj.magic 0)") {
					"(Obj.magic 0)";
				} else {
					final fullArgs = args.copy();
					for (_ in 0...missing) fullArgs.push(ENull);

					if (fullArgs.length == 0) {
						c + " ()";
					} else {
						c
						+ " "
						+ fullArgs
							.map(a -> "(" + exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass) + ")")
							.join(" ");
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
						"(not ("
						+ exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
						+ "))";
					case "-":
						(isFloatExpr(expr) ? "(-.(" : "(-(")
						+ exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
						+ "))";
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
								case EIdent(name)
									if (tyByIdent != null
										&& tyByIdent.get(name) != null
										&& tyByIdent.get(name).toString() == "Int"):
									"float_of_int " + ocamlValueIdent(name);
							case _:
								exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						}
					}
					switch (op) {
						case "+" if (isStringExpr(a) || isStringExpr(b)):
							"((" + exprToOcamlForConcat(a) + ") ^ (" + exprToOcamlForConcat(b) + "))";
						case "+" | "-" | "*" | "/" | "%":
							// Best-effort numeric lowering:
							// - if both sides look like floats, use OCaml float operators,
							// - if both sides look like ints, use OCaml int operators,
						// - otherwise, collapse to bring-up poison to avoid type errors.
							final aIsF = isFloatExpr(a);
							final bIsF = isFloatExpr(b);
							final aIsI = isIntExpr(a);
							final bIsI = isIntExpr(b);
							final canFloat = (op == "+" || op == "-" || op == "*" || op == "/");
							if ((aIsF || bIsF) && canFloat) {
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
							} else if ((aIsI && bIsI) || (!aIsF && !bIsF)) {
								"((" + la + ") " + op + " (" + rb + "))";
							} else {
								"(Obj.magic 0)";
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
							"((" + la + ") " + op + " (" + rb + "))";
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
					+ exprToOcaml(cond, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") then ("
					+ exprToOcaml(thenExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") else ("
					+ exprToOcaml(elseExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ "))";
			case ESwitch(scrutinee, cases):
				// Stage 3 bring-up: lower a small structured switch expression subset to nested `if`.
				//
				// We intentionally implement matching in terms of `Obj.repr` + `HxRuntime.dynamic_equals`
				// so we don't need to commit to concrete OCaml types for the scrutinee.
				final sw = exprToOcaml(scrutinee, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				var chain = "(Obj.magic HxRuntime.hx_null)";
					if (cases != null) {
						for (i in 0...cases.length) {
							final c = cases[cases.length - 1 - i];
							final localTy =
								switch (c.pattern) {
									case PBind(name):
										extendTyByIdent(tyByIdent, name, TyType.fromHintText("Dynamic"));
									case _:
										tyByIdent;
								};
							final body = exprToOcaml(c.expr, arityByIdent, localTy, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
							final thenExpr =
								switch (c.pattern) {
									case PBind(name):
										"(let " + ocamlValueIdent(name) + " = __sw in (" + body + "))";
									case _:
										"(" + body + ")";
								};
						final cond =
							switch (c.pattern) {
								case PNull:
									"(HxRuntime.is_null (Obj.repr __sw))";
								case PWildcard, PBind(_):
									"true";
								case PString(v):
									"(HxRuntime.dynamic_equals (Obj.repr __sw) (Obj.repr " + escapeOcamlString(v) + "))";
								case PInt(v):
									"(HxRuntime.dynamic_equals (Obj.repr __sw) (Obj.repr " + Std.string(v) + "))";
								case PEnumValue(name):
									"(HxRuntime.dynamic_equals (Obj.repr __sw) (Obj.repr " + escapeOcamlString(name) + "))";
							};
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
					final elems = values == null || values.length == 0
						? ""
						: values
							.map(v -> exprToOcaml(v, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass))
							.join("; ");
					"HxBootArray.of_list [" + elems + "]";
				case EArrayAccess(arr, idx):
					"HxBootArray.get ("
					+ exprToOcaml(arr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ") ("
					+ exprToOcaml(idx, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")";
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

	static function returnExprToOcaml(
		expr:HxExpr,
		allowedValueIdents:Map<String, Bool>,
		?arityByIdent:Map<String, Int>,
		?tyByIdent:Map<String, TyType>,
		?staticImportByIdent:Map<String, String>,
		?currentPackagePath:String,
		?moduleNameByPkgAndClass:Map<String, String>
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
					// `null` is representable as a runtime sentinel in the Stage3 bootstrap output.
					false;
				case EEnumValue(_):
					false;
				case EThis:
					true;
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
								hasBringupPoison(args[0]) || hasBringupPoison(args[1]);
							}
						case _:
							true;
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
					} else if (tyByIdent != null && tyByIdent.get(name) != null) {
						// Parameters and bound locals are safe to reference.
						false;
					} else if (allowedValueIdents != null && allowedValueIdents.get(name) == true) {
						false;
					} else if (staticImportByIdent != null && staticImportByIdent.get(name) != null) {
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
				case ESwitch(scrutinee, cases):
					if (hasBringupPoison(scrutinee)) {
						true;
					} else if (cases == null) {
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
						for (c in cases) {
							if (!hasBringupPoison(c.expr)) {
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
					if (hasBringupPoison(callee)) return true;
					for (a in args) if (hasBringupPoison(a)) return true;
					false;
					case EArrayDecl(values):
						for (v in values) if (hasBringupPoison(v)) return true;
						false;
					case EArrayComprehension(_name, iterable, yieldExpr):
						hasBringupPoison(iterable) || hasBringupPoison(yieldExpr);
					case EArrayAccess(arr, idx):
						hasBringupPoison(arr) || hasBringupPoison(idx);
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
		if (hasBringupPoison(expr)) return "(Obj.magic 0)";

		return exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
	}

	static function stmtListToOcaml(
		stmts:Array<HxStmt>,
		allowedValueIdents:Map<String, Bool>,
		returnExc:String,
		?arityByIdent:Map<String, Int>,
		?tyByIdent:Map<String, TyType>,
		?staticImportByIdent:Map<String, String>,
		?currentPackagePath:String,
		?moduleNameByPkgAndClass:Map<String, String>
	):String {
		if (stmts == null || stmts.length == 0) return "()";

		function stmtAlwaysReturns(s:HxStmt):Bool {
			return switch (s) {
				case SReturnVoid(_), SReturn(_, _):
					true;
				case SIf(_cond, thenBranch, elseBranch, _):
					elseBranch != null && stmtAlwaysReturns(thenBranch) && stmtAlwaysReturns(elseBranch);
				case SSwitch(_scrutinee, cases, _):
					// Bring-up: treat switches as non-returning unless every case body returns.
					if (cases == null || cases.length == 0) {
						false;
					} else {
						var all = true;
						for (c in cases) {
							if (!stmtAlwaysReturns(c.body)) {
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
					boolOrTrue(
						returnExprToOcaml(e, allowedValueIdents, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					);
				case EBinop(op, _, _) if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||"):
					boolOrTrue(
						returnExprToOcaml(e, allowedValueIdents, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					);
				case _:
					// Conservative default: we do not have real typing for conditions yet.
					// Keep bring-up resilient by treating unknown conditions as true.
					"true";
			};
		}

		function stmtToUnit(s:HxStmt):String {
			return switch (s) {
				case SBlock(ss, _pos):
					stmtListToOcaml(ss, allowedValueIdents, returnExc, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
				case SVar(_name, _typeHint, _init, _pos):
					// Handled at the list level because it needs to wrap the remainder with `let ... in`.
					"()";
				case SSwitch(scrutinee, cases, _pos):
					final sw = exprToOcaml(scrutinee, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
					var chain = "()";
					if (cases != null) {
						for (i in 0...cases.length) {
							final c = cases[cases.length - 1 - i];
							final bodyUnit = stmtToUnit(c.body);
							final thenUnit =
								switch (c.pattern) {
									case PBind(name):
										"(let " + ocamlValueIdent(name) + " = __sw in (" + bodyUnit + "))";
									case _:
										"(" + bodyUnit + ")";
								};
							final cond =
								switch (c.pattern) {
									case PNull:
										"(HxRuntime.is_null (Obj.repr __sw))";
									case PWildcard, PBind(_):
										"true";
									case PString(v):
										"(HxRuntime.dynamic_equals (Obj.repr __sw) (Obj.repr " + escapeOcamlString(v) + "))";
									case PInt(v):
										"(HxRuntime.dynamic_equals (Obj.repr __sw) (Obj.repr " + Std.string(v) + "))";
									case PEnumValue(name):
										"(HxRuntime.dynamic_equals (Obj.repr __sw) (Obj.repr " + escapeOcamlString(name) + "))";
								};
							chain = "(if " + cond + " then " + thenUnit + " else (" + chain + "))";
						}
					}
					"(let __sw = (" + sw + ") in " + chain + ")";
				case SIf(cond, thenBranch, elseBranch, _pos):
					final thenUnit = stmtToUnit(thenBranch);
					final elseUnit = elseBranch == null ? "()" : stmtToUnit(elseBranch);
					"if " + condToOcamlBool(cond) + " then (" + thenUnit + ") else (" + elseUnit + ")";
				case SForIn(name, iterable, body, _pos):
					final ident = ocamlValueIdent(name);
					final bodyUnit = stmtToUnit(body);
					switch (iterable) {
						case ERange(startExpr, endExpr):
							final start = exprToOcaml(startExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
							final end = exprToOcaml(endExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
							"(let __start = (" + start + ") in "
							+ "let __end = (" + end + ") in "
							+ "if (__end <= __start) then () else ("
							+ "for " + ident + " = __start to (__end - 1) do "
							+ bodyUnit
							+ " done))";
						case _:
							"HxBootArray.iter ("
							+ exprToOcaml(iterable, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") (fun " + ident + " -> " + bodyUnit + ")";
					}
				case SReturnVoid(_pos):
					"raise (" + returnExc + " (Obj.repr ()))";
				case SReturn(expr, _pos):
					"raise ("
					+ returnExc
					+ " (Obj.repr ("
					+ returnExprToOcaml(expr, allowedValueIdents, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
					+ ")))";
				case SExpr(expr, _pos):
					// Avoid emitting invalid OCaml when we parse Haxe assignment as `EBinop("=")`.
					switch (expr) {
						case EBinop("=", _l, _r):
							"()";
						case _:
							"ignore ("
							+ returnExprToOcaml(expr, allowedValueIdents, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
			}
		}
		}

		// Fold right so `var` statements can wrap the rest with `let name = init in ...`.
		var out = "()";
		for (i in 0...stmts.length) {
			final s = stmts[stmts.length - 1 - i];
			switch (s) {
					case SVar(name, _typeHint, init, _pos):
						final rhs =
							if (init == null) {
								"(Obj.magic 0)";
							} else {
								// Stage 3 bring-up: in class methods, `var x = x;` commonly means
								// "shadow a field" (`var x = this.x;`). We don't model `this` field
								// access yet, and emitting `let x = x` produces an unbound OCaml value.
								switch (init) {
									case EIdent(n) if (n == name):
										"(Obj.magic 0)";
									case _:
										returnExprToOcaml(
											init,
											allowedValueIdents,
											arityByIdent,
											tyByIdent,
											staticImportByIdent,
											currentPackagePath,
											moduleNameByPkgAndClass
										);
								}
							};
						final ident = ocamlValueIdent(name);
						// Keep OCaml warning discipline resilient: Haxe code (especially upstream-ish tests)
						// can contain locals that are intentionally unused. In OCaml, that triggers warnings
						// which can become hard errors under `-warn-error`.
					out = "let " + ident + " = " + rhs + " in (ignore " + ident + "; (" + out + "))";
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
						if (assign != null && isNullCheckFor(assign.name, cond)) {
							final ident = ocamlValueIdent(assign.name);
							final rhs = returnExprToOcaml(
								assign.rhs,
								allowedValueIdents,
								arityByIdent,
								tyByIdent,
								staticImportByIdent,
								currentPackagePath,
								moduleNameByPkgAndClass
							);
							out =
								"(let "
								+ ident
								+ " = (if "
								+ condToOcamlBool(cond)
								+ " then ("
								+ rhs
								+ ") else "
								+ ident
								+ ") in ("
								+ out
								+ "))";
						} else {
							// Default lowering for if-statements.
							out = stmtAlwaysReturns(s) ? stmtToUnit(s) : ("(" + stmtToUnit(s) + "; " + out + ")");
						}
				case _:
					// Avoid emitting `...; <nonreturning expr>` sequences, which produce warning 21
					// (nonreturning-statement). This also naturally drops statements that appear after
					// a definite `return` in the same block (unreachable in Haxe).
					out = stmtAlwaysReturns(s) ? stmtToUnit(s) : ("(" + stmtToUnit(s) + "; " + out + ")");
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

			function uniqStrings(xs:Array<String>):Array<String> {
				if (xs == null || xs.length <= 1) return xs;
				final seen = new Map<String, Bool>();
				final out = new Array<String>();
				for (x in xs) {
					if (x == null) continue;
					if (seen.exists(x)) continue;
					seen.set(x, true);
					out.push(x);
				}
				return out;
			}

			function ocamldepSort(mlFiles:Array<String>):Array<String> {
				if (mlFiles == null || mlFiles.length <= 1) return mlFiles;

				final ocamldep = {
					final v = Sys.getEnv("OCAMLDEP");
				(v == null || v.length == 0) ? "ocamldep" : v;
			}

			final p = new sys.io.Process(ocamldep, ["-I", "runtime", "-I", "+unix", "-I", "+str", "-sort"].concat(mlFiles));
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
		var shimRepoRoot = "";
		function inferRepoRootForShims():String {
			if (shimRepoRoot.length > 0) return shimRepoRoot;
			final env = Sys.getEnv("HXHX_REPO_ROOT");
			if (env != null && env.length > 0) {
				final candidate = haxe.io.Path.join([env, "packages", "hih-compiler", "shims"]);
				if (sys.FileSystem.exists(candidate) && sys.FileSystem.isDirectory(candidate)) {
					shimRepoRoot = env;
					return shimRepoRoot;
				}
			}

			final prog = Sys.programPath();
			if (prog == null || prog.length == 0) return "";
			final abs = try sys.FileSystem.fullPath(prog) catch (_:Dynamic) prog;
			var dir = try haxe.io.Path.directory(abs) catch (_:Dynamic) "";
			if (dir == null || dir.length == 0) return "";

			for (_ in 0...10) {
				final shimsDir = haxe.io.Path.join([dir, "packages", "hih-compiler", "shims"]);
				if (sys.FileSystem.exists(shimsDir) && sys.FileSystem.isDirectory(shimsDir)) {
					shimRepoRoot = dir;
					return shimRepoRoot;
				}
				final parent = haxe.io.Path.normalize(haxe.io.Path.join([dir, ".."]));
				if (parent == dir) break;
				dir = parent;
			}
			return "";
		}

			function readShimTemplate(shimName:String):String {
				final root = inferRepoRootForShims();
				if (root == null || root.length == 0) throw "stage3 emitter: cannot locate repo root for shim templates (set HXHX_REPO_ROOT)";
				final path = haxe.io.Path.join([root, "packages", "hih-compiler", "shims", shimName + ".ml"]);
				if (!sys.FileSystem.exists(path)) throw "stage3 emitter: missing shim template: " + path;
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
			// - These modules live in `std/runtime/*.ml` and are authored for this repo.
			// - They are **not** copied from upstream Haxe compiler sources.
			final runtimePaths = new Array<String>();
			{
				final root = inferRepoRootForShims();
				if (root == null || root.length == 0) throw "stage3 emitter: cannot locate repo root for runtime templates (set HXHX_REPO_ROOT)";
				final runtimeSrcDir = haxe.io.Path.join([root, "std", "runtime"]);
				if (!sys.FileSystem.exists(runtimeSrcDir) || !sys.FileSystem.isDirectory(runtimeSrcDir)) {
					throw "stage3 emitter: missing std/runtime directory: " + runtimeSrcDir;
				}

				final runtimeOutDir = haxe.io.Path.join([outAbs, "runtime"]);
				if (!sys.FileSystem.exists(runtimeOutDir)) sys.FileSystem.createDirectory(runtimeOutDir);

				for (name in sys.FileSystem.readDirectory(runtimeSrcDir)) {
					if (name == null || !StringTools.endsWith(name, ".ml")) continue;
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
			// Stage 3 bring-up: a tiny "array-like" container used only by the bootstrap emitter output.
			//
			// Why
			// - Gate2-shaped orchestration code uses `Array` pervasively and expects mutation (`push`)
			//   and iteration (`for (x in arr)`).
			// - The Stage3 bootstrap emitter deliberately does **not** link the full reflaxe.ocaml
			//   runtime (`std/runtime`), so we provide a self-contained OCaml shim here.
			//
			// Note
			// - This is not Haxe-correct `Array<T>` semantics. It is a bring-up convenience to let
			//   stage3_emit_runner style workloads execute far enough to expose the *next* missing
			//   frontend/typer/macro feature.
			final shimName = "HxBootArray";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath, readShimTemplate(shimName));
				generatedPaths.push(shimName + ".ml");
			}
		}
		{
			final shimName = "HxBootProcess";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(shimPath, readShimTemplate(shimName));
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
								+ "let copy = HxAnon.copy\n"
							);
						generatedPaths.push(shimName + ".ml");
					}
				}
			{
				final shimName = "IgnoredFixture";
				final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
				if (!sys.FileSystem.exists(shimPath)) {
					sys.io.File.saveContent(
						shimPath,
						"(* hxhx(stage3) bootstrap shim: IgnoredFixture *)\n"
						+ "type t = Obj.t\n"
						+ "let notIgnored _ = (Obj.magic 0)\n"
						+ "let ignored _ = (Obj.magic 0)\n"
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
			final shimName = "Haxe_Int64";
			final shimPath = haxe.io.Path.join([outAbs, shimName + ".ml"]);
			if (!sys.FileSystem.exists(shimPath)) {
				sys.io.File.saveContent(
					shimPath,
					"(* hxhx(stage3) bootstrap shim: haxe.Int64 (shape-only) *)\n"
					+ "type t = {\n"
					+ "  low : int;\n"
					+ "  high : int;\n"
					+ "}\n"
					+ "\n"
					+ "let make (low : int) (high : int) : t = { low; high }\n"
				);
				generatedPaths.push(shimName + ".ml");
			}
		}

		final typedModules = p.getTypedModules();
		if (typedModules.length == 0) throw "stage3 emitter: empty typed module graph";

		inline function moduleNameForDecl(decl:HxModuleDecl, className:String):String {
			final pkgRaw = decl == null ? "" : HxModuleDecl.getPackagePath(decl);
			final pkg = pkgRaw == null ? "" : StringTools.trim(pkgRaw);
			final parts = (pkg.length == 0 ? [] : pkg.split(".")).concat([className]);
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
			final cls = HxModuleDecl.getMainClass(decl);
			final className = HxClassDecl.getName(cls);
			if (className == null || className.length == 0 || className == "Unknown") continue;
			final pkgRaw = decl == null ? "" : HxModuleDecl.getPackagePath(decl);
			final pkg = pkgRaw == null ? "" : StringTools.trim(pkgRaw);
			final key = pkg + ":" + className;
			moduleNameByPkgAndClass.set(key, moduleNameForDecl(decl, className));
		}

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
		for (tm in typedModules) {
			final decl = tm.getParsed().getDecl();
			final cls = HxModuleDecl.getMainClass(decl);
			final className = HxClassDecl.getName(cls);
			if (className == null || className.length == 0 || className == "Unknown") continue;
			final modName = moduleNameForDecl(decl, className);

			final members:Map<String, Bool> = new Map();
			for (fn in HxClassDecl.getFunctions(cls)) {
				if (HxFunctionDecl.getIsStatic(fn)) members.set(HxFunctionDecl.getName(fn), true);
			}
			for (field in HxClassDecl.getFields(cls)) {
				if (HxFieldDecl.getIsStatic(field)) members.set(HxFieldDecl.getName(field), true);
			}
			staticMembersByModule.set(modName, members);
		}

			function emitModule(tm:TypedModule, isRoot:Bool):Null<String> {
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
					if (isRoot) return true;
					if (filePath == null || filePath.length == 0) return false;
					final p = filePath;
					final isStd = p.indexOf("/std/") != -1 || p.indexOf("\\std\\") != -1;
					return !isStd;
				}
				final moduleEmitBodies = emitFullBodies && allowFullBodiesForFile(tm.getParsed().getFilePath(), isRoot);

				final decl = tm.getParsed().getDecl();
				final mainClass = HxModuleDecl.getMainClass(decl);
				final className = HxClassDecl.getName(mainClass);
				if (className == null || className.length == 0 || className == "Unknown") return null;
			final moduleName = moduleNameForDecl(decl, className);

			final parsedFns = HxClassDecl.getFunctions(mainClass);
			final parsedByName = new Map<String, HxFunctionDecl>();
			for (fn in parsedFns) parsedByName.set(HxFunctionDecl.getName(fn), fn);

			final typedFns = tm.getEnv().getMainClass().getFunctions();
			final arityByName:Map<String, Int> = new Map();
			for (tf in typedFns) arityByName.set(tf.getName(), tf.getParams().length);

			// Best-effort `import Foo.Bar.*` support:
			// Build a map of unqualified identifiers -> imported module name for static members.
			final staticImportByIdent:Map<String, String> = new Map();
			for (rawImport in tm.getEnv().getImports()) {
				if (rawImport == null) continue;
				final imp = StringTools.trim(rawImport);
				if (!StringTools.endsWith(imp, ".*")) continue;

				final base = imp.substr(0, imp.length - 2);
				final importModName = ocamlModuleNameFromTypePath(base);
				if (importModName.length == 0) continue;

				final members = staticMembersByModule.get(importModName);
				if (members == null) continue;
				for (name in members.keys()) {
					if (!staticImportByIdent.exists(name)) staticImportByIdent.set(name, importModName);
				}
			}

			final out = new Array<String>();
			out.push("(* Generated by hxhx(stage3) bootstrap emitter *)");
			out.push("");

			// Emit class-scope static values (bootstrap subset).
			//
			// Why
			// - Upstream harness code relies on `static final` constants (Ints/Strings + simple if/switch).
			// - Without emitting these as OCaml `let` bindings, references collapse to bring-up poison.
			final parsedFields = HxClassDecl.getFields(mainClass);
			for (f in parsedFields) {
				if (!HxFieldDecl.getIsStatic(f)) continue;
				final nameRaw = HxFieldDecl.getName(f);
				if (nameRaw == null || nameRaw.length == 0) continue;
				final init = HxFieldDecl.getInit(f);
				final initOcaml = init == null
					? "(Obj.magic 0)"
					: exprToOcaml(
						init,
						arityByName,
						null,
						staticImportByIdent,
						HxModuleDecl.getPackagePath(decl),
						moduleNameByPkgAndClass
					);
				out.push("let " + ocamlValueIdent(nameRaw) + " = " + initOcaml);
			}
			if (parsedFields.length > 0) out.push("");

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
					// Allow unqualified references to static fields/constants in the same module.
					for (f in parsedFields) if (HxFieldDecl.getIsStatic(f)) allowed.set(HxFieldDecl.getName(f), true);
					function collectLocalNamesInStmt(s:HxStmt, out:Map<String, Bool>):Void {
						switch (s) {
							case SBlock(stmts, _):
								for (ss in stmts) collectLocalNamesInStmt(ss, out);
							case SIf(_cond, thenBranch, elseBranch, _):
								collectLocalNamesInStmt(thenBranch, out);
								if (elseBranch != null) collectLocalNamesInStmt(elseBranch, out);
							case SForIn(name, _iterable, body, _):
								out.set(name, true);
								collectLocalNamesInStmt(body, out);
							case SVar(name, _hint, _init, _):
								out.set(name, true);
							case _:
						}
					}

					// Only allow locals when we're actually emitting statement bodies that bind them.
					// Use the parsed statement list (not the typed-local list) so we don't accidentally
					// "allow" identifiers that won't be bound in emitted OCaml.
					if (moduleEmitBodies && parsedFn != null) {
						final localNames:Map<String, Bool> = new Map();
						for (s in HxFunctionDecl.getBody(parsedFn)) collectLocalNamesInStmt(s, localNames);
						for (name in localNames.keys()) allowed.set(name, true);
						// Keep type hints for those locals when available.
						for (l in tf.getLocals()) if (allowed.get(l.getName()) == true) tyByIdent.set(l.getName(), l.getType());
					}

					// Ensure allowed identifiers are treated as bound during emission, even if we don't know
					// their precise type yet. This avoids `exprToOcaml` collapsing locals/helpers to bring-up
					// poison purely because Stage3 typing info is incomplete.
					for (name in allowed.keys()) if (tyByIdent.get(name) == null) tyByIdent.set(name, TyType.unknown());

					final body = if (parsedFn == null) {
						"()";
					} else if (!moduleEmitBodies) {
						returnExprToOcaml(
							parsedFn.getFirstReturnExpr(),
							allowed,
							arityByName,
							tyByIdent,
							staticImportByIdent,
							HxModuleDecl.getPackagePath(decl),
							moduleNameByPkgAndClass
						);
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
					// - Use `let _ = <stmts> in (Obj.magic 0)` for the no-return path and cast the entire
					//   `try` to `retTy`.
					// - This is intentionally non-semantic but avoids OCaml type errors like:
					//   "This variant expression is expected to have type bool; There is no constructor () within type bool".
						"((" //
						+ "try (let _ = "
						+ stmtListToOcaml(
							stmts,
							allowed,
							exc,
							arityByName,
							tyByIdent,
							staticImportByIdent,
							HxModuleDecl.getPackagePath(decl),
							moduleNameByPkgAndClass
						)
						+ " in (Obj.magic 0)) "
						+ "with " + exc + " v -> (Obj.magic v)"
						+ ") : " + retTy + ")";
					};

				// Keep return type annotation to make early typing behavior visible.
				final kw = i == 0 ? "let rec" : "and";
				out.push(kw + " " + name + " " + ocamlArgs + " : " + retTy + " = " + body);
				out.push("");
				}

				if (moduleEmitBodies && exceptions.length > 0) {
					// Prepend exceptions so the `try ... with` clauses can reference them.
					out.insert(2, exceptions.join("\n") + "\n");
				}

			if (isRoot && sawMain) {
				out.push("let () = ignore (main ())");
				out.push("");
			}

			final mlPath = haxe.io.Path.join([outAbs, moduleName + ".ml"]);
			sys.io.File.saveContent(mlPath, out.join("\n"));
			return moduleName + ".ml";
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
				final orderedMl = uniqStrings(ocamldepSort(uniqStrings(runtimePaths.concat(generatedPaths).concat(emittedModulePaths))));
			final orderedNoRoot = new Array<String>();
			final rootName = rootPath;
			for (f in orderedMl) if (rootName == null || f != rootName) orderedNoRoot.push(f);
			if (rootName != null) orderedNoRoot.push(rootName);
			final orderedNoRootUniq = uniqStrings(orderedNoRoot);

				final args = new Array<String>();
				// OCaml 5: make the unix stdlib include directory explicit to silence the
				// "ocaml_deprecated_auto_include" warning.
				args.push("-I");
				args.push("+unix");
				args.push("-I");
				args.push("+str");
				// Allow emitted units in `outAbs/` to see providers compiled under `outAbs/runtime/`.
				args.push("-I");
				args.push("runtime");
				args.push("-o");
				args.push("out.exe");
				// Link the OCaml stdlib packages used by our runtime and shims.
				args.push("unix.cmxa");
				args.push("str.cmxa");
				for (p in orderedNoRootUniq) args.push(p);
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
