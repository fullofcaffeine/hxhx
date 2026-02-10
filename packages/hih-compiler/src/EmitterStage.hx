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

private typedef EmitterCallSig = {
	/** Total OCaml parameters after lowering (includes the rest-array parameter when present). */
	final expected:Int;
	/** Number of fixed (non-rest) parameters. */
	final fixed:Int;
	/** Whether the final parameter is a lowered rest-args array. */
	final hasRest:Bool;
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
	public static function traceCallSig(modName:String, fnName:String, args:Array<HxFunctionArg>, fixed:Int, hasRest:Bool):Void {
		final enabled = Sys.getEnv("HXHX_TRACE_CALLSIG");
		if (enabled != "1" && enabled != "true" && enabled != "yes") return;
		if (!hasRest) return;
		try {
			final parts = new Array<String>();
			if (args != null) {
				for (a in args) {
					final nm = HxFunctionArg.getName(a);
					final kind = HxFunctionArg.getIsRest(a) ? "rest" : "fixed";
					parts.push(nm + ":" + kind);
				}
			}
			Sys.stderr().writeString(
				"callsig " + modName + "." + fnName + " fixed=" + fixed + " hasRest=" + (hasRest ? "1" : "0") + " args=[" + parts.join(",") + "]\n"
			);
		} catch (_:Dynamic) {}
	}
}

class EmitterStage {
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

		static function exprToOcamlString(
			e:HxExpr,
			?tyByIdent:Map<String, TyType>,
			?arityByIdent:Map<String, Int>,
			?staticImportByIdent:Map<String, String>,
			?currentPackagePath:String,
			?moduleNameByPkgAndClass:Map<String, String>,
			?callSigByCallee:Map<String, EmitterCallSig>
		):String {
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
							"HxRuntime.dynamic_toStdString (Obj.repr ("
								+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
								+ "))";
				case ECall(EField(_obj, "join"), [_sep]):
					// Bring-up: join returns a string; delegate to normal expression lowering when available.
							exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
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
						: ("HxRuntime.dynamic_toStdString (Obj.repr (" + ocamlValueIdent(name) + "))");
				case EIdent(name)
					if (tyByIdent != null
						&& tyByIdent.get(name) != null
						&& tyByIdent.get(name).toString() == "Array"):
					"HxRuntime.dynamic_toStdString (Obj.repr (" + ocamlValueIdent(name) + "))";
			case _:
				// Bring-up default: prefer *some* stringification over `<unsupported>` so
				// upstream harness logs remain readable (and don't change meaning).
				//
				// Note: this uses the backend's `Std.string` implementation (Haxe semantics),
				// not OCaml's `Stdlib.string_of_*`.
						"HxRuntime.dynamic_toStdString (Obj.repr ("
							+ exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
							+ "))";
		}
	}

				static function exprToOcaml(
					e:HxExpr,
					?arityByIdent:Map<String, Int>,
					?tyByIdent:Map<String, TyType>,
					?staticImportByIdent:Map<String, String>,
					?currentPackagePath:String,
					?moduleNameByPkgAndClass:Map<String, String>,
					?callSigByCallee:Map<String, EmitterCallSig>
				):String {
				inline function tyForIdent(name:String):String {
					if (tyByIdent == null) return "";
					final t = tyByIdent.get(name);
					return t == null ? "" : t.toString();
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

			function isFloatExpr(expr:HxExpr):Bool {
				return switch (expr) {
					case EFloat(_):
						true;
					case EIdent(name):
						tyForIdent(name) == "Float";
					case EBinop("/", a, b):
						// Division yields Float for numeric Int/Float operands in Haxe.
						// For non-numeric/abstract cases we collapse emission to bring-up poison, so
						// we only treat it as float-ish when both sides look numeric.
						isFloatExpr(a) || isFloatExpr(b) || (isIntExpr(a) && isIntExpr(b));
					case EBinop(op, a, b) if (op == "+" || op == "-" || op == "*"):
						// Best-effort: propagate float-ness through arithmetic.
						isFloatExpr(a) || isFloatExpr(b);
					case ETernary(_cond, thenExpr, elseExpr):
						isFloatExpr(thenExpr) && isFloatExpr(elseExpr);
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
					case EUnop("-", inner):
						// Make sure negative int literals become floats in float contexts.
						"(-.(" + exprToOcamlAsFloatValue(inner) + "))";
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
					// Stage 3 bring-up: map a tiny slice of `haxe.Int64` construction helpers.
					//
					// Why
					// - Upstream `haxe.io.FPHelper` initializes `static var i64tmp = Int64.ofInt(0);`.
					// - OCaml's `Int64` module uses snake_case (`of_int`), and in bootstrap we model
					//   `haxe.Int64` as a small record (`Haxe_Int64.t`), not as OCaml's native int64.
					//
					// What
					// - Lower `Int64.ofInt(i)` to our shim `Haxe_Int64.ofInt(i)`.
					// - Lower `Int64.make(lo, hi)` to `Haxe_Int64.make(lo, hi)`.
					case ECall(EField(EIdent("Int64"), "ofInt"), [arg])
						| ECall(EField(EIdent("haxe.Int64"), "ofInt"), [arg]):
						"Haxe_Int64.ofInt ("
							+ exprToOcaml(arg, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case ECall(EField(EIdent("Int64"), "make"), [lo, hi])
						| ECall(EField(EIdent("haxe.Int64"), "make"), [lo, hi]):
						"Haxe_Int64.make ("
							+ exprToOcaml(lo, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ") ("
							+ exprToOcaml(hi, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
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

				// Stage 3 bring-up: `StringTools.hex(n)` is used in upstream unit code but our
				// bootstrap emitter doesn't model optional parameters.
				//
				// Haxe: `hex(n, ?digits)` defaults `digits` to 0.
				// OCaml: we emit a fixed-arity `StringTools.hex n digits`, so supply `0` when omitted.
				case ECall(EField(EIdent("StringTools"), "hex"), [n]):
					"StringTools.hex ("
					+ exprToOcaml(n, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ") (0)";

					case ECall(EField(EIdent("StringTools"), "replace"), [_s, _sub, _by]):
					// Bring-up: avoid needing a real `StringTools` implementation in the Stage3 emitter output.
					escapeOcamlString("");

				case ECall(EField(EIdent("Std"), "is"), [_v, _t]):
					// Bring-up: type tests require RTTI/runtime; keep compilation moving.
					"true";
				case ECall(EField(EIdent("Std"), "downcast"), [_value, _cls]):
					// Bring-up: `Std.downcast` requires RTTI/class objects. We don't model those in the
					// Stage3 emitter output yet, so collapse to `null`.
					"(Obj.magic HxRuntime.hx_null)";

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
						"print_endline (" + exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")";
					case ECall(EField(EIdent("Sys"), "println"), [arg]):
						"print_endline (" + exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")";
					case ECall(EField(EIdent("Sys"), "print"), [arg]):
						"print_string (" + exprToOcamlString(arg, tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")";
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
								final start = exprToOcaml(startExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
								final end = exprToOcaml(endExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
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
								// Bring-up default:
								// - In many upstream harness shapes, locals like `args` come from `Sys.args()`.
								// - Stage3 typing does not always preserve `Array<T>` for these locals, but
								//   treating `.length` as array length is far safer than collapsing to poison
								//   (poison in conditions can lead to out-of-bounds access and segfaults).
								return "HxBootArray.length (" + o + ")";
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
						// If the type path is relative to the current package, prefer resolving it within the
						// current package (or its parent packages) when we know a matching emitted module exists.
						//
						// Example:
						// - Haxe: `package demo; class A { static function f() Util.ping(); }`
						// - OCaml: `Demo_Util.ping ()` (not `Util.ping ()`)
						//
						// Also covers module-local helper types referenced as `Module.Helper`:
						// - Haxe: `package unit; ... MyMacro.MyRestMacro.testRest1(...)`
						// - OCaml: `Unit_MyMacro_MyRestMacro.testRest1 ...`
						//
						// Upstream also resolves unqualified type names by walking up parent packages.
						// Example:
						// - `package runci.targets; ... Linux.requireAptPackages(...)` resolves to `runci.Linux`
						//   even without an explicit import.
						if (moduleNameByPkgAndClass != null) {
							final raw = parts.join(".");
							var cur = currentPackagePath == null ? "" : StringTools.trim(currentPackagePath);
							while (true) {
								final key = cur + ":" + raw;
								final local = moduleNameByPkgAndClass.get(key);
								if (local != null && local.length > 0) {
									modName = local;
									break;
								}
								if (cur.length == 0) break;
								final lastDot = cur.lastIndexOf(".");
								cur = lastDot < 0 ? "" : cur.substr(0, lastDot);
							}
						}
						// Import-based resolution for type short names that would otherwise collide
						// with OCaml stdlib modules.
						//
						// Example (upstream unit suite):
						// - Haxe: `import haxe.Int64.*; Int64.mul(a, b);`
						// - OCaml: `Haxe_Int64.mul a b` (not `Int64.mul a b` from stdlib)
						if (parts.length == 1 && parts[0] == "Int64" && currentImportInt64 != null && currentImportInt64.length > 0) {
							modName = currentImportInt64;
						}
						(currentOcamlModuleName != null && modName == currentOcamlModuleName)
							? ocamlValueIdent(field)
							: (modName + "." + ocamlValueIdent(field));
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
							// Stage 3 emit-runner bring-up: map `sys.FileSystem` statics used by RunCi to the
							// repo-owned OCaml runtime implementation (`std/runtime/HxFileSystem.ml`).
							//
							// Why
							// - Upstream `tests/runci/Config.hx` imports `sys.FileSystem` and then calls
							//   `FileSystem.fullPath(...)` in static initializers.
							// - Our bootstrap emitter doesn't yet resolve imported type short-names to OCaml
							//   module paths, so it would otherwise emit `FileSystem.fullPath` (unbound).
							//
							// Scope
							// - Minimal set needed by Gate2 bring-up; expand as upstream workloads demand.
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
							// Stage 3 emit-runner bring-up: map `sys.io.File` statics used by RunCi targets to
							// the repo-owned OCaml runtime implementation (`std/runtime/HxFile.ml`).
							//
							// Why
							// - Upstream runci targets often `import sys.io.File;` and then call `File.saveContent(...)`.
							// - The bootstrap emitter does not yet emit the full std `sys.io.File` module, so we
							//   treat a small set of whole-file operations as intrinsics backed by `HxFile`.
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
							// Gate2 bring-up: avoid depending on the std `Xml` implementation while still compiling
							// upstream harness code that parses remote appcasts.
							//
							// Stage3 emit-runner does not execute these code paths on most platforms, but it must
							// successfully compile the RunCi harness (which references Flash target helpers).
							case EField(EIdent("Xml"), "parse") if (args.length == 1):
								return "(Obj.magic 0)";
							// Path joining (haxe.io.Path), used by upstream RunCi config.
							case EField(EIdent("Path"), "join") if (args.length == 1):
								return "HxBootArray.join ("
									+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
									+ ") (\"/\") (fun (s : string) -> s)";
							// Bring-up: `haxe.io.Path.normalize(path)` (used by Flash target).
							case EField(EIdent("Path"), "normalize") if (args.length == 1):
								return "HxFileSystem.normalize_path ("
									+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
									+ ")";
							// Bring-up: `haxe.io.Path.directory(path)` and `using haxe.io.Path; path.directory()`.
							case EField(EIdent("Path"), "directory") if (args.length == 1):
								return "Filename.dirname ("
									+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
									+ ")";
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
							return "print_endline (" + exprToOcamlString(args[0], tyByIdent, arityByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")";
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
						return "HxSys.getEnv ("
							+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
							+ ")";
					case EField(EIdent("Sys"), "environment") if (args.length == 0):
						return "(HxSys.environment ())";
					case EField(EIdent("Sys"), "args") if (args.length == 0):
						// Haxe: Sys.args() excludes argv[0].
						return "(let __argv = Stdlib.Sys.argv in "
							+ "let __len = Array.length __argv in "
							+ "if __len <= 1 then HxBootArray.create () "
							+ "else HxBootArray.of_list (Array.to_list (Array.sub __argv 1 (__len - 1))))";
					case EField(EIdent("Sys"), "putEnv") if (args.length == 2):
						// Haxe: `Sys.putEnv(name, value)` accepts null for removal.
						// Our runtime provides the option-based API; bridge through the hx_null sentinel.
						final rawName = exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						final rawValue = exprToOcaml(args[1], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass);
						return "(let __v = Obj.repr (" + rawValue + ") in "
							+ "let __opt : string option = if __v == HxRuntime.hx_null then None else Some (Obj.obj __v) in "
							+ "HxSys.putEnv (" + rawName + ") __opt)";
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
							case EField(obj, "toArray") if (args.length == 0):
								// Rest-args bring-up: upstream code frequently calls `rest.toArray()` where
								// `rest` originates from a `...args:T` parameter.
								//
								// We lower rest params to `Array<T>`, so treat `toArray()` as identity.
								switch (obj) {
									case EArrayDecl(_):
										return exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
									case EIdent(name):
										final t = tyForIdent(name);
										if (t == "Array" || StringTools.startsWith(t, "Array<")) {
											return exprToOcaml(obj, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
										}
									case _:
								}
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
									case ECall(EField(EIdent(name), "toArray"), []):
										// Common upstream shape:
										//   `rest.toArray().join(sep)`
										//
										// We lower rest params to `Array<T>` and `toArray()` to identity, so treat this as
										// `rest.join(sep)` when the type is `Array<String>`.
										final t = tyForIdent(name);
										if (t == "Array<String>" || t == "Array< String >" || t.indexOf("Array<String>") == 0) {
											return "HxBootArray.join ("
												+ exprToOcaml(EIdent(name), arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
												+ ") ("
												+ exprToOcaml(args[0], arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
												+ ") (fun (s : string) -> s)";
										}
									case _:
								}
						case _:
					}

					final c = exprToOcaml(callee, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
				// Safety: if the callee is already "bring-up poison", do not apply arguments.
				//
				// Why
				// - Applying args to a non-function expression produces OCaml warnings/errors
				//   and can cascade into type mismatches.
				// - In bring-up we prefer collapsing to poison over producing invalid OCaml.
					if (c == "(Obj.magic 0)") {
						"(Obj.magic 0)";
					} else {
								final sig = (callSigByCallee == null) ? null : callSigByCallee.get(c);

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
						if (arityByIdent != null && arityByIdent.exists(c) && args.length > arityByIdent.get(c)) {
							if (sig == null || !sig.hasRest) return "(Obj.magic 0)";
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
							for (i in 0...fixedCount) fixedArgs.push(i < args.length ? args[i] : ENull);
							final restArgs = (args.length > fixedCount) ? args.slice(fixedCount) : [];
							final restCode =
								(restArgs.length == 0)
									? "HxBootArray.create ()"
									: ("HxBootArray.of_list ["
										+ restArgs
											.map(a -> exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee))
											.join("; ")
										+ "]");

							final argCodes = new Array<String>();
							for (a in fixedArgs) {
								argCodes.push("(" + exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")");
							}
							argCodes.push("(" + restCode + ")");

							c + " " + argCodes.join(" ");
						} else {
							var missingCount = missing;
							if (missingCount == 0 && sig != null) {
								final expected = sig.expected;
								if (expected > args.length) missingCount = expected - args.length;
								}
	
								var fullArgs = args.copy();

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
										for (i in 0...prefixLen) adjusted.push(fullArgs[i]);
										for (_ in 0...missingBefore) adjusted.push(ENull);
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
							for (_ in 0...missingCount) fullArgs.push(ENull);

							if (fullArgs.length == 0) {
								c + " ()";
							} else {
								c
								+ " "
								+ fullArgs
									.map(a -> "(" + exprToOcaml(a, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee) + ")")
									.join(" ");
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
								case EUnop("-", inner):
									// Promote negative int literals/expressions to float too.
									"(-.(" + exprToOcamlAsFloat(inner) + "))";
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
						case "/":
							// Bring-up compromise:
							// - When both sides look numeric (`Int`/`Float`), follow Haxe and emit float division.
							// - Otherwise, collapse to bring-up poison to avoid type errors for abstract/operator-
							//   overloaded cases (e.g. upstream Int64 tests).
							final aIsF = isFloatExpr(a);
							final bIsF = isFloatExpr(b);
							final aIsI = isIntExpr(a);
							final bIsI = isIntExpr(b);
							((aIsF || bIsF) || (aIsI && bIsI))
								? "((" + exprToOcamlAsFloat(a) + ") /. (" + exprToOcamlAsFloat(b) + "))"
								: "(Obj.magic 0)";
							case "+" | "-" | "*" | "%":
								// Best-effort numeric lowering:
								// - if both sides look like floats, use OCaml float operators,
								// - if both sides look like ints, use OCaml int operators,
							// - otherwise, collapse to bring-up poison to avoid type errors.
								final aIsF = isFloatExpr(a);
								final bIsF = isFloatExpr(b);
								final aIsI = isIntExpr(a);
								final bIsI = isIntExpr(b);
								final canFloat = (op == "+" || op == "-" || op == "*" || op == "/");
								if (op == "%") {
									if (aIsF || bIsF) {
										final fa = exprToOcamlAsFloat(a);
										final fb = exprToOcamlAsFloat(b);
										"(mod_float (" + fa + ") (" + fb + "))";
									} else if (aIsI && bIsI) {
										"((" + la + ") mod (" + rb + "))";
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
					+ exprToOcaml(cond, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ") then ("
					+ exprToOcaml(thenExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ ") else ("
					+ exprToOcaml(elseExpr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
					+ "))";
			case ESwitch(scrutinee, cases):
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
								for (pp in patterns) parts.push("(" + patternCond(pp) + ")");
								"(" + parts.join(" || ") + ")";
							}
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
				}
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
							final body = exprToOcaml(c.expr, arityByIdent, localTy, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
							// Switch expressions can legitimately unify unrelated branch types in Haxe
							// (e.g. `case OpAdd: Int`, `case OpEq: Bool`), but OCaml requires a single
							// expression type for the whole `if ... then ... else ...` chain.
							//
							// Bring-up strategy: cast each branch to `Obj.t` to keep emission resilient.
							final bodyAsDynamic = "(Obj.magic (" + body + "))";
							final thenExpr =
								switch (c.pattern) {
									case PBind(name):
										"(let " + ocamlValueIdent(name) + " = __sw in (" + bodyAsDynamic + "))";
									case _:
										"(" + bodyAsDynamic + ")";
								};
						final cond = patternCond(c.pattern);
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
							// Use `Obj.magic` per element so mixed-type array literals (common in upstream tests,
							// e.g. `[1, "hello"]`) remain OCaml-typecheckable during bring-up.
							.map(v ->
								"(Obj.magic ("
								+ exprToOcaml(v, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass)
								+ "))"
							)
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
				?expectedReturnType:TyType,
				?arityByIdent:Map<String, Int>,
				?tyByIdent:Map<String, TyType>,
				?staticImportByIdent:Map<String, String>,
				?currentPackagePath:String,
				?moduleNameByPkgAndClass:Map<String, String>,
			?callSigByCallee:Map<String, EmitterCallSig>
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
							case EIdent(name) if (tyByIdent != null && tyByIdent.get(name) != null && tyByIdent.get(name).toString() == "Int"):
								"float_of_int " + ocamlValueIdent(name);
							case _:
								exprToOcaml(e, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
						}
					}
					return switch (expr) {
						case EInt(_):
							asFloatValue(expr);
						case EUnop("-", inner):
							"(-.(" + asFloatValue(inner) + "))";
						case _:
							exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
					}
				}

				return exprToOcaml(expr, arityByIdent, tyByIdent, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee);
			}

		static function stmtListToOcaml(
			stmts:Array<HxStmt>,
			allowedValueIdents:Map<String, Bool>,
			returnExc:String,
			?arityByIdent:Map<String, Int>,
			?tyByIdent:Map<String, TyType>,
			?staticImportByIdent:Map<String, String>,
			?currentPackagePath:String,
			?moduleNameByPkgAndClass:Map<String, String>,
			?callSigByCallee:Map<String, EmitterCallSig>,
			?localTypeHints:Map<String, TyType>,
			?fnReturnTypes:Map<String, TyType>
		):String {
			if (stmts == null || stmts.length == 0) return "()";

			// Stage 3 bring-up: merge any precomputed local type hints with a tiny, local
			// initializer-based inference pass so later statements can emit more correct OCaml.
			//
			// Example (upstream unit/TestNaN.hx):
			// - `var a = foo(); if (a > 0) ...`
			// - Even if the typer can't infer `a` from the call site, we can approximate it
			//   from the known return type of `foo` in the same module.
			final localHints:Map<String, TyType> = new Map();
			if (localTypeHints != null) for (k in localTypeHints.keys()) localHints.set(k, localTypeHints.get(k));

			function inferInitType(e:HxExpr):TyType {
				if (e == null) return TyType.unknown();
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
					case ECall(EIdent(fn), _args) if (fnReturnTypes != null && fnReturnTypes.get(fn) != null):
						fnReturnTypes.get(fn);
					case _:
						TyType.unknown();
				}
			}

			function seedLocalHintsFromStmts(ss:Array<HxStmt>):Void {
				if (ss == null) return;
				for (s in ss) {
					switch (s) {
						case SVar(name, _hint, init, _pos):
							if (name == null || name.length == 0) continue;
							final existing = localHints.get(name);
							final inferred = inferInitType(init);
							if (existing == null || (existing.isUnknown() && !inferred.isUnknown())) {
								localHints.set(name, inferred);
							}
						case _:
					}
				}
			}

			seedLocalHintsFromStmts(stmts);

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
					for (k in m.keys()) out.set(k, m.get(k));
					return out;
				}

				if (stmts == null) return before;
				for (s in stmts) {
					before.push(cloneMap(cur));
					switch (s) {
						case SVar(name, _hint, _init, _pos):
							if (name != null && name.length > 0) cur.set(name, true);
						case _:
					}
				}
				return before;
			}

			function extendTyWithLocals(base:Null<Map<String, TyType>>, locals:Null<Map<String, Bool>>):Map<String, TyType> {
				if (locals == null) return base == null ? new Map() : base;
				var any = false;
				for (_k in locals.keys()) {
					any = true;
					break;
				}
				if (!any) return base == null ? new Map() : base;

				final out:Map<String, TyType> = new Map();
				if (base != null) for (k in base.keys()) out.set(k, base.get(k));
				for (name in locals.keys()) {
					if (out.get(name) == null) {
						final hinted = localHints.get(name);
						out.set(name, hinted != null ? hinted : TyType.unknown());
					}
				}
				return out;
			}

			function extendTyByIdentLocal(ty:Null<Map<String, TyType>>, name:String, t:TyType):Map<String, TyType> {
				final out:Map<String, TyType> = new Map();
				if (ty != null) for (k in ty.keys()) out.set(k, ty.get(k));
				out.set(name, t);
				return out;
			}

			final localsBefore = localsInScopeBefore(stmts);

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

			function condToOcamlBool(e:HxExpr, tyCtx:Null<Map<String, TyType>>):String {
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
									returnExprToOcaml(e, allowedValueIdents, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
								);
						case EBinop(op, _, _) if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=" || op == "&&" || op == "||"):
								boolOrTrue(
									returnExprToOcaml(e, allowedValueIdents, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
								);
					case _:
						// Conservative default: we do not have real typing for conditions yet.
						// Keep bring-up resilient by treating unknown conditions as true.
					"true";
			};
		}

			function stmtToUnit(s:HxStmt, tyCtx:Null<Map<String, TyType>>):String {
				return switch (s) {
					case SBlock(ss, _pos):
						stmtListToOcaml(
							ss,
							allowedValueIdents,
							returnExc,
							arityByIdent,
							tyCtx,
							staticImportByIdent,
							currentPackagePath,
							moduleNameByPkgAndClass,
							callSigByCallee,
							localHints,
							fnReturnTypes
						);
					case SVar(_name, _typeHint, _init, _pos):
						// Handled at the list level because it needs to wrap the remainder with `let ... in`.
						"()";
					case SSwitch(scrutinee, cases, _pos):
						final sw =
							exprToOcaml(
								scrutinee,
								arityByIdent,
								tyCtx,
								staticImportByIdent,
								currentPackagePath,
								moduleNameByPkgAndClass,
								callSigByCallee
							);
					function patternCond(p:HxSwitchPattern):String {
						return switch (p) {
							case POr(patterns):
								if (patterns == null || patterns.length == 0) {
									"false";
								} else {
									final parts = new Array<String>();
									for (pp in patterns) parts.push("(" + patternCond(pp) + ")");
									"(" + parts.join(" || ") + ")";
								}
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
					}
						var chain = "()";
						if (cases != null) {
							for (i in 0...cases.length) {
								final c = cases[cases.length - 1 - i];
								final caseTy =
									switch (c.pattern) {
										case PBind(name):
											extendTyByIdentLocal(tyCtx, name, TyType.fromHintText("Dynamic"));
										case _:
											tyCtx;
									};
								final bodyUnit = stmtToUnit(c.body, caseTy);
								final thenUnit =
									switch (c.pattern) {
										case PBind(name):
											"(let " + ocamlValueIdent(name) + " = __sw in (" + bodyUnit + "))";
										case _:
											"(" + bodyUnit + ")";
									};
								final cond = patternCond(c.pattern);
								chain = "(if " + cond + " then " + thenUnit + " else (" + chain + "))";
							}
						}
						"(let __sw = (" + sw + ") in " + chain + ")";
					case SIf(cond, thenBranch, elseBranch, _pos):
						final thenUnit = stmtToUnit(thenBranch, tyCtx);
						final elseUnit = elseBranch == null ? "()" : stmtToUnit(elseBranch, tyCtx);
						final condS = condToOcamlBool(cond, tyCtx);
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
						case SForIn(name, iterable, body, _pos):
						final ident = ocamlValueIdent(name);
						final bodyTy = extendTyByIdentLocal(tyCtx, name, TyType.fromHintText("Dynamic"));
						final bodyUnit = stmtToUnit(body, bodyTy);
						switch (iterable) {
							case ERange(startExpr, endExpr):
								final start =
									exprToOcaml(
										startExpr,
										arityByIdent,
										tyCtx,
										staticImportByIdent,
										currentPackagePath,
										moduleNameByPkgAndClass,
										callSigByCallee
									);
								final end =
									exprToOcaml(
										endExpr,
										arityByIdent,
										tyCtx,
										staticImportByIdent,
										currentPackagePath,
										moduleNameByPkgAndClass,
										callSigByCallee
									);
							"(let __start = (" + start + ") in "
							+ "let __end = (" + end + ") in "
							+ "if (__end <= __start) then () else ("
							+ "for " + ident + " = __start to (__end - 1) do "
							+ bodyUnit
								+ " done))";
								case _:
									"HxBootArray.iter ("
									+ exprToOcaml(iterable, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
									+ ") (fun " + ident + " -> " + bodyUnit + ")";
						}
					case SReturnVoid(_pos):
						"raise (" + returnExc + " (Obj.repr ()))";
					case SReturn(expr, _pos):
							"raise ("
								+ returnExc
								+ " (Obj.repr ("
								+ returnExprToOcaml(expr, allowedValueIdents, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
								+ ")))";
					case SExpr(expr, _pos):
						// Avoid emitting invalid OCaml when we parse Haxe assignment as `EBinop("=")`.
						switch (expr) {
							case EBinop("=", _l, _r):
								"()";
									case _:
										"ignore ("
										+ returnExprToOcaml(expr, allowedValueIdents, null, arityByIdent, tyCtx, staticImportByIdent, currentPackagePath, moduleNameByPkgAndClass, callSigByCallee)
										+ ")";
				}
			}
			}

			// Fold right so `var` statements can wrap the rest with `let name = init in ...`.
			var out = "()";
			for (i in 0...stmts.length) {
				final idx = stmts.length - 1 - i;
				final s = stmts[idx];
				final tyCtx = extendTyWithLocals(tyByIdent, localsBefore[idx]);
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
														null,
														arityByIdent,
														tyCtx,
														staticImportByIdent,
														currentPackagePath,
														moduleNameByPkgAndClass,
													callSigByCallee
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
											null,
											arityByIdent,
											tyCtx,
											staticImportByIdent,
											currentPackagePath,
											moduleNameByPkgAndClass,
										callSigByCallee
									);
								out =
									"(let "
									+ ident
									+ " = (if "
									+ condToOcamlBool(cond, tyCtx)
									+ " then ("
									+ rhs
									+ ") else "
									+ ident
									+ ") in (ignore "
									+ ident
									+ "; ("
									+ out
									+ ")))";
							} else {
								// Default lowering for if-statements.
								out = stmtAlwaysReturns(s) ? stmtToUnit(s, tyCtx) : ("(" + stmtToUnit(s, tyCtx) + "; " + out + ")");
							}
					case _:
						// Avoid emitting `...; <nonreturning expr>` sequences, which produce warning 21
						// (nonreturning-statement). This also naturally drops statements that appear after
						// a definite `return` in the same block (unreachable in Haxe).
						out = stmtAlwaysReturns(s) ? stmtToUnit(s, tyCtx) : ("(" + stmtToUnit(s, tyCtx) + "; " + out + ")");
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
					+ "let parseString (_s : string) : t = 0\n"
					+ "let toInt (v : t) : int = v\n"
					+ "let toStr (v : t) : string = string_of_int v\n"
					+ "let add (a : t) (b : t) : t = a + b\n"
					+ "let sub (a : t) (b : t) : t = a - b\n"
					+ "let mul (a : t) (b : t) : t = a * b\n"
					+ "let neg (a : t) : t = (-a)\n"
					+ "let compare (a : t) (b : t) : int = Stdlib.compare a b\n"
					+ "let divMod (a : t) (b : t) : divmod =\n"
					+ "  if b = 0 then { quotient = 0; modulus = 0 } else { quotient = a / b; modulus = a mod b }\n"
					+ "let isInt64 (_ : Obj.t) : bool = true\n"
				);
				generatedPaths.push(shimName + ".ml");
			}
		}

		final typedModules = p.getTypedModules();
		if (typedModules.length == 0) throw "stage3 emitter: empty typed module graph";

		// Stage 3 bring-up: avoid emitting placeholder units that shadow the repo-owned runtime.
		//
		// Why
		// - We copy `std/runtime/*.ml` into `out/runtime/` and compile them as part of the Stage3 program.
		// - The Stage3 typer/emitter can still produce placeholder `*.ml` units for the corresponding
		//   Haxe std types (e.g. `haxe.CallStack`), which would overwrite the runtime `.cmi` and cause
		//   downstream "Unbound value" errors.
		//
		// How
		// - Build a set of runtime-provided OCaml module names and skip emitting any typed module whose
		//   main unit name collides with a runtime unit.
		inline function runtimeModuleNameFromPath(path:String):String {
			final file = haxe.io.Path.withoutDirectory(path);
			final base = StringTools.endsWith(file, ".ml") ? file.substr(0, file.length - 3) : file;
			return upperFirst(base);
		}
		final runtimeModuleNames:Map<String, Bool> = new Map();
		for (p0 in runtimePaths) runtimeModuleNames.set(runtimeModuleNameFromPath(p0), true);
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

		inline function expectedMainClassFromFile(filePath:Null<String>):Null<String> {
			if (filePath == null || filePath.length == 0) return null;
			final name = haxe.io.Path.withoutDirectory(filePath);
			final dot = name.lastIndexOf(".");
			return dot <= 0 ? name : name.substr(0, dot);
		}

			inline function moduleTypeNameFor(tm:TypedModule):Null<String> {
				// In Haxe, the module name is the file base name (not "the first class we happened to parse").
				//
				// This matters for multi-type modules like upstream `unit/MyAbstract.hx`, where helper types are
				// addressed as `unit.MyAbstract.HelperType` regardless of which class the frontend surfaced as
				// the "main class" during bring-up.
				final fromFile = expectedMainClassFromFile(tm == null ? null : tm.getParsed().getFilePath());
				if (fromFile != null && fromFile.length > 0) return fromFile;

				// Fallback (in-memory modules): use the parsed main class name when available.
				final decl = tm == null ? null : tm.getParsed().getDecl();
				final main = decl == null ? null : HxModuleDecl.getMainClass(decl);
				final nm0 = main == null ? null : HxClassDecl.getName(main);
				final nm = nm0 == null ? "" : StringTools.trim(nm0);
				return (nm.length > 0 && nm != "Unknown") ? nm : null;
			}

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
			if (modName.length > 0 && modName != "Unknown" && typeName != modName) parts.push(modName);
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
					if (className == null || className.length == 0 || className == "Unknown") continue;
					final emitted = moduleNameForDecl(decl, moduleTypeName, className);

					// Key 1: `<pkg>:<ClassName>` for unqualified references (`Util.foo()`).
					//
					// Note: this is ambiguous for module-local helper types that share a short name
					// across modules, but it is a useful bring-up heuristic and matches prior behavior.
					final key = pkg + ":" + className;
					if (!moduleNameByPkgAndClass.exists(key)) moduleNameByPkgAndClass.set(key, emitted);

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
					if (!moduleNameByPkgAndClass.exists(keyRel)) moduleNameByPkgAndClass.set(keyRel, emitted);
				}
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
				for (k in runtimeModuleNames.keys()) existingMods.set(k, true);
				for (tm in typedModules) {
					final decl = tm.getParsed().getDecl();
					final moduleTypeName = moduleTypeNameFor(tm);
					for (cls in HxModuleDecl.getClasses(decl)) {
						final className = HxClassDecl.getName(cls);
						if (className == null || className.length == 0 || className == "Unknown") continue;
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
				]) deny.set(m, true);

				final aliasByShort:Map<String, String> = new Map();
				for (tm in typedModules) {
					for (rawImport in tm.getEnv().getImports()) {
						if (rawImport == null) continue;
						final imp = StringTools.trim(rawImport);
						if (imp.length == 0) continue;
						if (StringTools.endsWith(imp, ".*")) continue;
						final parts = imp.split(".");
						if (parts.length == 0) continue;
						final short = parts[parts.length - 1];
						if (short == null || short.length == 0 || !isUpperStart(short)) continue;
						if (deny.exists(short)) continue;
						// Don't alias over a real provider.
						if (existingMods.exists(short)) continue;
						final target = ocamlModuleNameFromTypePath(imp);
						if (target == null || target.length == 0) continue;
						if (target == short) continue;
						// Only alias to a provider that actually exists in this build output.
						if (!existingMods.exists(target)) continue;
						if (!aliasByShort.exists(short)) aliasByShort.set(short, target);
					}
				}

				for (short in aliasByShort.keys()) {
					final target = aliasByShort.get(short);
					if (target == null || target.length == 0) continue;
					var arr = aliasShortsByTarget.get(target);
					if (arr == null) {
						arr = [];
						aliasShortsByTarget.set(target, arr);
					}
					if (arr.indexOf(short) == -1) arr.push(short);
				}
			}

			// Call signature index used by `exprToOcaml` to avoid OCaml partial application when the
			// Haxe call site omits optional/default/rest parameters.
			//
			// Keys match the emitted OCaml callee expression:
			// - Qualified: `ModuleName.fn`
			// - (Module-local unqualified keys are added per-module in `emitModule`.)
				final globalCallSigByCallee:Map<String, EmitterCallSig> = new Map();
				for (tm in typedModules) {
					final decl = tm.getParsed().getDecl();
					final moduleTypeName = moduleTypeNameFor(tm);
					for (cls in HxModuleDecl.getClasses(decl)) {
						final className = HxClassDecl.getName(cls);
						if (className == null || className.length == 0 || className == "Unknown") continue;
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
							if (HxFieldDecl.getIsStatic(field)) members.set(HxFieldDecl.getName(field), true);
						}
						staticMembersByModule.set(modName, members);

						// Record qualified function signatures so call sites can:
						// - pack rest args (`...args:T`) into an array,
						// - and fill missing optional args with `null` to avoid partial application.
						for (fn in HxClassDecl.getFunctions(cls)) {
							final fnNameRaw = HxFunctionDecl.getName(fn);
							if (fnNameRaw == null || fnNameRaw.length == 0) continue;

							final fnArgs = HxFunctionDecl.getArgs(fn);
							final argCount = fnArgs == null ? 0 : fnArgs.length;
							// Robust rest detection:
							// - In valid Haxe syntax, the rest arg (if present) is the *last* parameter.
							// - During bring-up, we prefer a rule that can't be confused by accidental rest
							//   markings on earlier parameters (which would otherwise pack all args).
							var hasRest = false;
							var fixedCount = argCount;
							if (argCount > 0 && HxFunctionArg.getIsRest(fnArgs[argCount - 1])) {
								hasRest = true;
								fixedCount = argCount - 1;
								}
	
								final expected = fixedCount + (hasRest ? 1 : 0);
								_EmitterStageDebug.traceCallSig(modName, ocamlValueIdent(fnNameRaw), fnArgs, fixedCount, hasRest);
								final sig0:EmitterCallSig = { expected: expected, fixed: fixedCount, hasRest: hasRest };
								final key0 = modName + "." + ocamlValueIdent(fnNameRaw);
								globalCallSigByCallee.set(key0, sig0);
								final aliasShorts = aliasShortsByTarget.get(modName);
								if (aliasShorts != null) {
									for (short in aliasShorts) {
										globalCallSigByCallee.set(short + "." + ocamlValueIdent(fnNameRaw), sig0);
									}
								}
							}
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
					if (isRoot) return true;
					if (filePath == null || filePath.length == 0) return false;
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
					if (className == null || className.length == 0 || className == "Unknown") return { files: [], rootMain: null };
					final mainModuleName = moduleNameForDecl(decl, moduleTypeName, className);
					final isRuntimeProvided = runtimeModuleNames.exists(mainModuleName);

					// Import-driven resolution for `Int64.<field>` (Haxe `haxe.Int64` vs OCaml stdlib `Int64`).
					function findInt64ImportTarget(imports:Array<String>):Null<String> {
						if (imports == null) return null;
						for (rawImport in imports) {
							if (rawImport == null) continue;
							final imp0 = StringTools.trim(rawImport);
							if (imp0.length == 0) continue;
							final base = StringTools.endsWith(imp0, ".*") ? imp0.substr(0, imp0.length - 2) : imp0;
							final parts = base.split(".");
							if (parts.length == 0) continue;
							final short = parts[parts.length - 1];
							if (short != "Int64") continue;
							final target = ocamlModuleNameFromTypePath(base);
							if (target != null && target.length > 0 && target != "Unknown") return target;
						}
						return null;
					}

					final importInt64 = findInt64ImportTarget(tm.getEnv().getImports());

					function emitStubClass(cls:HxClassDecl):Null<String> {
						final nm = HxClassDecl.getName(cls);
						if (nm == null || nm.length == 0 || nm == "Unknown") return null;
						final moduleName = moduleNameForDecl(decl, moduleTypeName, nm);

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
								out.push("    let acc2 = (String.make 1 hexChars.[digit]) ^ acc in");
								out.push("    let x2 = Int32.shift_right_logical x 4 in");
								out.push("    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2");
								out.push("  in");
								out.push("  let s = build n32 \"\" in");
								out.push("  if digits <= 0 then s else");
								out.push("    let rec pad (s0 : string) : string =");
								out.push("      if String.length s0 < digits then pad (\"0\" ^ s0) else s0");
								out.push("    in");
								out.push("    pad s");
								out.push("");
							}

							// Emit static fields (best-effort).
							final parsedFields = HxClassDecl.getFields(cls);
							final staticTyByIdent:Map<String, TyType> = new Map();
							for (f in parsedFields) {
								if (!HxFieldDecl.getIsStatic(f)) continue;
								final nameRaw = HxFieldDecl.getName(f);
								if (nameRaw == null || nameRaw.length == 0) continue;
								final init = HxFieldDecl.getInit(f);
								final initOcaml = init == null
									? "(Obj.magic HxRuntime.hx_null)"
									: exprToOcaml(
										init,
										null,
										staticTyByIdent,
										null,
										HxModuleDecl.getPackagePath(decl),
										moduleNameByPkgAndClass,
										globalCallSigByCallee
									);
								out.push("let " + ocamlValueIdent(nameRaw) + " = " + initOcaml);
								out.push("");
								// Treat the binding as "known" for subsequent static inits, even without a real type.
								if (staticTyByIdent.get(nameRaw) == null) staticTyByIdent.set(nameRaw, TyType.unknown());
							}

							// Emit function stubs with correct arity to avoid OCaml partial application issues.
							for (fn in HxClassDecl.getFunctions(cls)) {
								final nameRaw = HxFunctionDecl.getName(fn);
								if (nameRaw == null || nameRaw.length == 0) continue;
								if (hasStringToolsHex && nameRaw == "hex") continue;
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

							final mlPath = haxe.io.Path.join([outAbs, moduleName + ".ml"]);
							sys.io.File.saveContent(mlPath, out.join("\n"));
							currentImportInt64 = prevInt64;
							return moduleName + ".ml";
						} catch (e:Dynamic) {
							currentImportInt64 = prevInt64;
							throw e;
						}
					}

					function emitMainClass():Null<String> {
						final prevOcamlModule = currentOcamlModuleName;
						final prevInt64 = currentImportInt64;
						currentOcamlModuleName = mainModuleName;
						currentImportInt64 = importInt64;
						try {
						final parsedFns = HxClassDecl.getFunctions(mainClass);
						final parsedByName = new Map<String, HxFunctionDecl>();
						for (fn in parsedFns) parsedByName.set(HxFunctionDecl.getName(fn), fn);

						final typedFns = tm.getEnv().getMainClass().getFunctions();
						final arityByName:Map<String, Int> = new Map();
					for (tf in typedFns) arityByName.set(tf.getName(), tf.getParams().length);
					final fnReturnTypesByName:Map<String, TyType> = new Map();
					for (tf in typedFns) fnReturnTypesByName.set(tf.getName(), tf.getReturnType());

					// Provide both:
					// - qualified signatures (all modules) for `Pkg_Mod.fn(...)` style calls,
					// - and unqualified signatures (this module) for `fn(...)` calls.
					final callSigByCallee:Map<String, EmitterCallSig> = new Map();
					for (k in globalCallSigByCallee.keys()) callSigByCallee.set(k, globalCallSigByCallee.get(k));
					for (fn in parsedFns) {
						final fnNameRaw = HxFunctionDecl.getName(fn);
						if (fnNameRaw == null || fnNameRaw.length == 0) continue;
					final fnArgs = HxFunctionDecl.getArgs(fn);
					final argCount = fnArgs == null ? 0 : fnArgs.length;
					var hasRest = false;
					var fixedCount = argCount;
					if (argCount > 0 && HxFunctionArg.getIsRest(fnArgs[argCount - 1])) {
						hasRest = true;
						fixedCount = argCount - 1;
					}
						final expected = fixedCount + (hasRest ? 1 : 0);
						_EmitterStageDebug.traceCallSig(mainModuleName, ocamlValueIdent(fnNameRaw), fnArgs, fixedCount, hasRest);
						callSigByCallee.set(ocamlValueIdent(fnNameRaw), { expected: expected, fixed: fixedCount, hasRest: hasRest });
					}

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
				// Keep bring-up output warning-clean under strict dune setups.
				// These warnings are common when we use `Obj.magic` / exception-return tricks.
				out.push("[@@@warning \"-21-26\"]");
				out.push("");

				final parsedFields = HxClassDecl.getFields(mainClass);

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
					if (!HxFieldDecl.getIsStatic(f)) continue;
					final n = HxFieldDecl.getName(f);
					if (n != null && n.length > 0) staticFieldNames.set(n, true);
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
						if (!HxFieldDecl.getIsStatic(f)) continue;
						final init = HxFieldDecl.getInit(f);
						if (init != null) staticInitWorklist.push(init);
					}
					while (staticInitWorklist.length > 0) {
						final e = staticInitWorklist.pop();
						if (e == null) continue;
						switch (e) {
							case ECall(callee, args):
								switch (callee) {
									case EIdent(name):
										if (name != null && name.length > 0) staticInitCalls.set(name, true);
									case EField(_obj, field):
										if (field != null && field.length > 0) staticInitCalls.set(field, true);
									case _:
								}
								if (callee != null) staticInitWorklist.push(callee);
								if (args != null) for (a in args) if (a != null) staticInitWorklist.push(a);
							case EField(obj, _):
								if (obj != null) staticInitWorklist.push(obj);
							case ELambda(_, body):
								if (body != null) staticInitWorklist.push(body);
							case ETernary(cond, thenExpr, elseExpr):
								if (cond != null) staticInitWorklist.push(cond);
								if (thenExpr != null) staticInitWorklist.push(thenExpr);
								if (elseExpr != null) staticInitWorklist.push(elseExpr);
							case EAnon(_, values):
								if (values != null) for (v in values) if (v != null) staticInitWorklist.push(v);
							case ESwitch(scrutinee, cases):
								if (scrutinee != null) staticInitWorklist.push(scrutinee);
								if (cases != null) for (c in cases) if (c != null && c.expr != null) staticInitWorklist.push(c.expr);
							case ENew(_, args):
								if (args != null) for (a in args) if (a != null) staticInitWorklist.push(a);
							case EUnop(_, expr):
								if (expr != null) staticInitWorklist.push(expr);
							case EBinop(_, left, right):
								if (left != null) staticInitWorklist.push(left);
								if (right != null) staticInitWorklist.push(right);
							case EArrayComprehension(_, iterable, yieldExpr):
								if (iterable != null) staticInitWorklist.push(iterable);
								if (yieldExpr != null) staticInitWorklist.push(yieldExpr);
							case EArrayDecl(values):
								if (values != null) for (v in values) if (v != null) staticInitWorklist.push(v);
							case EArrayAccess(array, index):
								if (array != null) staticInitWorklist.push(array);
								if (index != null) staticInitWorklist.push(index);
							case ERange(start, end):
								if (start != null) staticInitWorklist.push(start);
								if (end != null) staticInitWorklist.push(end);
							case ECast(expr, _):
								if (expr != null) staticInitWorklist.push(expr);
							case EUntyped(expr):
								if (expr != null) staticInitWorklist.push(expr);
							case _:
						}
					}

				final fnNames:Map<String, Bool> = new Map();
				for (tf in typedFns) {
					final n = tf.getName();
					if (n != null && n.length > 0) fnNames.set(n, true);
				}

				final preludeFnNames:Map<String, Bool> = new Map();
				for (name in staticInitCalls.keys()) {
					if (!fnNames.exists(name)) continue;
					if (name == "load") continue;
					preludeFnNames.set(name, true);
				}

				function collectLocalsFromStmt(s:HxStmt, locals:Map<String, Bool>):Void {
					switch (s) {
						case SBlock(stmts, _):
							if (stmts != null) for (ss in stmts) collectLocalsFromStmt(ss, locals);
						case SVar(name, _, _, _):
							if (name != null && name.length > 0) locals.set(name, true);
						case SIf(_, thenBranch, elseBranch, _):
							collectLocalsFromStmt(thenBranch, locals);
							if (elseBranch != null) collectLocalsFromStmt(elseBranch, locals);
						case SForIn(name, _, body, _):
							if (name != null && name.length > 0) locals.set(name, true);
							collectLocalsFromStmt(body, locals);
						case SSwitch(_, cases, _):
							if (cases != null) for (c in cases) collectLocalsFromStmt(c.body, locals);
						case _:
					}
				}

				function scanExprForDeps(e:Null<HxExpr>, locals:Map<String, Bool>, calls:Map<String, Bool>, idents:Map<String, Bool>):Void {
					if (e == null) return;
					switch (e) {
						case EIdent(name):
							if (name != null && name.length > 0 && !locals.exists(name)) idents.set(name, true);
						case EField(obj, _):
							scanExprForDeps(obj, locals, calls, idents);
						case ECall(callee, args):
							switch (callee) {
								case EIdent(name):
									if (name != null && name.length > 0 && !locals.exists(name)) calls.set(name, true);
								case EField(_obj, field):
									if (field != null && field.length > 0 && !locals.exists(field)) calls.set(field, true);
								case _:
							}
							scanExprForDeps(callee, locals, calls, idents);
							if (args != null) for (a in args) scanExprForDeps(a, locals, calls, idents);
						case ELambda(args, body):
							final nestedLocals:Map<String, Bool> = new Map();
							for (k in locals.keys()) nestedLocals.set(k, true);
							if (args != null) for (a in args) if (a != null && a.length > 0) nestedLocals.set(a, true);
							scanExprForDeps(body, nestedLocals, calls, idents);
						case ETernary(cond, thenExpr, elseExpr):
							scanExprForDeps(cond, locals, calls, idents);
							scanExprForDeps(thenExpr, locals, calls, idents);
							scanExprForDeps(elseExpr, locals, calls, idents);
						case EAnon(_, values):
							if (values != null) for (v in values) scanExprForDeps(v, locals, calls, idents);
						case ESwitch(scrutinee, cases):
							scanExprForDeps(scrutinee, locals, calls, idents);
							if (cases != null) for (c in cases) scanExprForDeps(c.expr, locals, calls, idents);
						case ENew(_, args):
							if (args != null) for (a in args) scanExprForDeps(a, locals, calls, idents);
						case EUnop(_, expr):
							scanExprForDeps(expr, locals, calls, idents);
						case EBinop(_, left, right):
							scanExprForDeps(left, locals, calls, idents);
							scanExprForDeps(right, locals, calls, idents);
						case EArrayComprehension(name, iterable, yieldExpr):
							final nestedLocals:Map<String, Bool> = new Map();
							for (k in locals.keys()) nestedLocals.set(k, true);
							if (name != null && name.length > 0) nestedLocals.set(name, true);
							scanExprForDeps(iterable, locals, calls, idents);
							scanExprForDeps(yieldExpr, nestedLocals, calls, idents);
						case EArrayDecl(values):
							if (values != null) for (v in values) scanExprForDeps(v, locals, calls, idents);
						case EArrayAccess(array, index):
							scanExprForDeps(array, locals, calls, idents);
							scanExprForDeps(index, locals, calls, idents);
						case ERange(start, end):
							scanExprForDeps(start, locals, calls, idents);
							scanExprForDeps(end, locals, calls, idents);
						case ECast(expr, _):
							scanExprForDeps(expr, locals, calls, idents);
						case EUntyped(expr):
							scanExprForDeps(expr, locals, calls, idents);
						case _:
					}
				}

				function scanStmtForDeps(s:HxStmt, locals:Map<String, Bool>, calls:Map<String, Bool>, idents:Map<String, Bool>):Void {
					switch (s) {
						case SBlock(stmts, _):
							if (stmts != null) for (ss in stmts) scanStmtForDeps(ss, locals, calls, idents);
						case SVar(_name, _typeHint, init, _):
							scanExprForDeps(init, locals, calls, idents);
						case SIf(cond, thenBranch, elseBranch, _):
							scanExprForDeps(cond, locals, calls, idents);
							scanStmtForDeps(thenBranch, locals, calls, idents);
							if (elseBranch != null) scanStmtForDeps(elseBranch, locals, calls, idents);
						case SForIn(_name, iterable, body, _):
							scanExprForDeps(iterable, locals, calls, idents);
							scanStmtForDeps(body, locals, calls, idents);
						case SSwitch(scrutinee, cases, _):
							scanExprForDeps(scrutinee, locals, calls, idents);
							if (cases != null) for (c in cases) scanStmtForDeps(c.body, locals, calls, idents);
						case SReturn(expr, _):
							scanExprForDeps(expr, locals, calls, idents);
						case SExpr(expr, _):
							scanExprForDeps(expr, locals, calls, idents);
						case _:
					}
				}

					final fnCallsByName:Map<String, Map<String, Bool>> = new Map();
					final fnRefsStaticByName:Map<String, Bool> = new Map();
					function analyzeFn(nameRaw:String):Void {
						if (fnCallsByName.exists(nameRaw)) return;
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
							if (pn != null && pn.length > 0) locals.set(pn, true);
						}
						for (s in HxFunctionDecl.getBody(parsedFn)) collectLocalsFromStmt(s, locals);
						final idents:Map<String, Bool> = new Map();
						for (s in HxFunctionDecl.getBody(parsedFn)) scanStmtForDeps(s, locals, calls, idents);
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
						final calls = fnCallsByName.get(nameRaw);
						if (calls == null) continue;
						for (callee in calls.keys()) {
							if (!fnNames.exists(callee)) continue;
							if (callee == "load") continue;
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
					if (fnRefsStaticByName.get(nameRaw) == true) preludeFnNames.remove(nameRaw);
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
					if (tf.getName() != "load") continue;
					final nameRaw = tf.getName();
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
					for (name in allowed.keys()) if (tyByIdent.get(name) == null) tyByIdent.set(name, TyType.unknown());
					final body = parsedFn == null
						? "(Obj.magic 0)"
						: returnExprToOcaml(
							parsedFn.getFirstReturnExpr(),
							allowed,
							tf.getReturnType(),
							arityByName,
							tyByIdent,
							staticImportByIdent,
							HxModuleDecl.getPackagePath(decl),
							moduleNameByPkgAndClass,
							callSigByCallee
						);

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
					if (nameRaw == null || nameRaw.length == 0) continue;
					if (!preludeFnNames.exists(nameRaw)) continue;
					typedFnsPrelude.push(tf);
				}

				function emitFnGroup(group:Array<TyFunctionEnv>):Void {
					for (i in 0...group.length) {
						final tf = group[i];
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
						for (tf2 in typedFns) allowed.set(tf2.getName(), true);
						for (f in parsedFields) if (HxFieldDecl.getIsStatic(f)) allowed.set(HxFieldDecl.getName(f), true);

						final localTypeHints:Map<String, TyType> = new Map();
						if (moduleEmitBodies) {
							for (l in tf.getLocals()) {
								final n = l.getName();
								if (n != null && n.length > 0 && localTypeHints.get(n) == null) localTypeHints.set(n, l.getType());
							}
						}

						for (name in allowed.keys()) if (tyByIdent.get(name) == null) tyByIdent.set(name, TyType.unknown());

						final body = if (parsedFn == null) {
							"()";
						} else if (!moduleEmitBodies) {
							returnExprToOcaml(
								parsedFn.getFirstReturnExpr(),
								allowed,
								tf.getReturnType(),
								arityByName,
								tyByIdent,
								staticImportByIdent,
								HxModuleDecl.getPackagePath(decl),
								moduleNameByPkgAndClass,
								callSigByCallee
							);
						} else {
							final exc = "HxReturn_" + escapeOcamlIdentPart(nameRaw);
							exceptions.push("exception " + exc + " of Obj.t");
							final stmts = HxFunctionDecl.getBody(parsedFn);
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
								moduleNameByPkgAndClass,
								callSigByCallee,
								localTypeHints,
								fnReturnTypesByName
							)
							+ " in (Obj.magic 0)) "
							+ "with " + exc + " v -> (Obj.magic v)"
							+ ") : " + retTy + ")";
						};

						final kw = i == 0 ? "let rec" : "and";
						out.push(kw + " " + name + " " + ocamlArgs + " : " + retTy + " = " + body);
						out.push("");
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
					if (!HxFieldDecl.getIsStatic(f)) continue;
					final nameRaw = HxFieldDecl.getName(f);
					if (nameRaw == null || nameRaw.length == 0) continue;
					final init = HxFieldDecl.getInit(f);
					final initOcaml = init == null
						? "(Obj.magic 0)"
						: exprToOcaml(
							init,
							arityByName,
							staticTyByIdent,
							staticImportByIdent,
							HxModuleDecl.getPackagePath(decl),
							moduleNameByPkgAndClass,
							callSigByCallee
						);
					out.push("let " + ocamlValueIdent(nameRaw) + " = " + initOcaml);
					if (staticTyByIdent.get(nameRaw) == null) staticTyByIdent.set(nameRaw, TyType.unknown());
				}
				if (parsedFields.length > 0) out.push("");

					final typedFnsRest = new Array<TyFunctionEnv>();
					for (tf in typedFns) {
						if (shouldHoistLoad && tf.getName() == "load") continue;
						if (preludeFnNames.exists(tf.getName())) continue;
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
							if (nm != null && nm.length > 0) restIndexByName.set(nm, i);
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
						for (i in 0...nRest) seenStamp[i] = 0;

						for (i in 0...nRest) {
							final nameRaw = typedFnsRest[i].getName();
							final parsedFn = nameRaw == null ? null : parsedByName.get(nameRaw);
							if (parsedFn == null) continue;

							final stamp = i + 1;
							final stmtWorklist = new Array<HxStmt>();
							final exprWorklist = new Array<HxExpr>();
							for (s in HxFunctionDecl.getBody(parsedFn)) if (s != null) stmtWorklist.push(s);

							while (stmtWorklist.length > 0) {
								final s = stmtWorklist.pop();
								if (s == null) continue;
								switch (s) {
									case SBlock(stmts, _):
										if (stmts != null) for (ss in stmts) if (ss != null) stmtWorklist.push(ss);
									case SVar(_name, _hint, init, _):
										if (init != null) exprWorklist.push(init);
									case SIf(cond, thenBranch, elseBranch, _):
										if (cond != null) exprWorklist.push(cond);
										if (thenBranch != null) stmtWorklist.push(thenBranch);
										if (elseBranch != null) stmtWorklist.push(elseBranch);
									case SForIn(_name, iterable, body, _):
										if (iterable != null) exprWorklist.push(iterable);
										if (body != null) stmtWorklist.push(body);
									case SSwitch(scrutinee, cases, _):
										if (scrutinee != null) exprWorklist.push(scrutinee);
										if (cases != null) for (c in cases) if (c != null && c.body != null) stmtWorklist.push(c.body);
									case SReturnVoid(_):
									case SReturn(expr, _):
										if (expr != null) exprWorklist.push(expr);
									case SExpr(expr, _):
										if (expr != null) exprWorklist.push(expr);
								}
							}

							while (exprWorklist.length > 0) {
								final e = exprWorklist.pop();
								if (e == null) continue;
								switch (e) {
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

										if (callee != null) exprWorklist.push(callee);
										if (args != null) for (a in args) if (a != null) exprWorklist.push(a);
									case EField(obj, _):
										if (obj != null) exprWorklist.push(obj);
									case ELambda(_args, body):
										if (body != null) exprWorklist.push(body);
									case ETernary(cond, thenExpr, elseExpr):
										if (cond != null) exprWorklist.push(cond);
										if (thenExpr != null) exprWorklist.push(thenExpr);
										if (elseExpr != null) exprWorklist.push(elseExpr);
									case EAnon(_names, values):
										if (values != null) for (v in values) if (v != null) exprWorklist.push(v);
									case ESwitch(scrutinee, cases):
										if (scrutinee != null) exprWorklist.push(scrutinee);
										if (cases != null) for (c in cases) if (c != null && c.expr != null) exprWorklist.push(c.expr);
									case ENew(_typePath, args):
										if (args != null) for (a in args) if (a != null) exprWorklist.push(a);
									case EUnop(_op, expr):
										if (expr != null) exprWorklist.push(expr);
									case EBinop(_op, left, right):
										if (left != null) exprWorklist.push(left);
										if (right != null) exprWorklist.push(right);
									case EArrayComprehension(_name, iterable, yieldExpr):
										if (iterable != null) exprWorklist.push(iterable);
										if (yieldExpr != null) exprWorklist.push(yieldExpr);
									case EArrayDecl(values):
										if (values != null) for (v in values) if (v != null) exprWorklist.push(v);
									case EArrayAccess(array, index):
										if (array != null) exprWorklist.push(array);
										if (index != null) exprWorklist.push(index);
									case ERange(start, end):
										if (start != null) exprWorklist.push(start);
										if (end != null) exprWorklist.push(end);
									case ECast(expr, _hint):
										if (expr != null) exprWorklist.push(expr);
									case EUntyped(expr):
										if (expr != null) exprWorklist.push(expr);
									case _:
								}
							}
						}

						// Kosaraju SCC on the function dependency graph.
						final visited = new Array<Int>();
						visited.resize(nRest);
						for (i in 0...nRest) visited[i] = 0;
						final order = new Array<Int>();

						for (v in 0...nRest) {
							if (visited[v] != 0) continue;
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
						for (i in 0...nRest) compId[i] = -1;
						final comps = new Array<Array<Int>>();

						var oi = order.length - 1;
						while (oi >= 0) {
							final v = order[oi];
							oi -= 1;
							if (compId[v] != -1) continue;

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
						for (k in 0...compEdgeSeen.length) compEdgeSeen[k] = 0;

						for (i in 0...nRest) {
							final callerComp = compId[i];
							final adj = edges[i];
							if (adj == null) continue;
							for (j in adj) {
								final calleeComp = compId[j];
								if (callerComp == calleeComp) continue;
								// Emit callee SCC before caller SCC.
								final src = calleeComp;
								final dst = callerComp;
								final key = src * nComp + dst;
								if (compEdgeSeen[key] != 0) continue;
								compEdgeSeen[key] = 1;
								compAdj[src].push(dst);
								indeg[dst] += 1;
							}
						}

						final q = new Array<Int>();
						for (c in 0...nComp) if (indeg[c] == 0) q.push(c);
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
									if (indeg[d] == 0) q.push(d);
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
								if (nodes != null) for (idx in nodes) group.push(typedFnsRest[idx]);
								if (group.length > 0) emitFnGroup(group);
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
						currentImportInt64 = prevInt64;
						return mainModuleName + ".ml";
						} catch (e:Dynamic) {
							currentOcamlModuleName = prevOcamlModule;
							currentImportInt64 = prevInt64;
							throw e;
						}
				}

					final files = new Array<String>();
					var rootMain:Null<String> = null;

					// Emit the main class first (typed, optional full bodies).
					final mainPath = isRuntimeProvided ? null : emitMainClass();
					if (mainPath != null) {
						files.push(mainPath);
						if (isRoot) rootMain = mainPath;
					}

					// Emit any additional module-local class declarations as separate compilation units.
					//
					// Why
					// - Upstream Haxe modules can declare helper types in the same file (often `private class Foo`).
					// - Stage3 typing currently models only the chosen `mainClass`, but codegen still needs
					//   providers for referenced static members like `Foo.bar`.
					for (c in HxModuleDecl.getClasses(decl)) {
						final nm = HxClassDecl.getName(c);
						if (nm == null || nm.length == 0 || nm == "Unknown") continue;
						if (nm == className) continue;
						final p = emitStubClass(c);
						if (p != null) files.push(p);
					}

					return { files: files, rootMain: rootMain };
				}

			// Emit dependencies first, but link the root module last so its `let () = main ()`
			// runs after all referenced compilation units are linked.
			final emittedModulePaths = new Array<String>();
			var rootMainPath:Null<String> = null;
			final deps = typedModules.slice(1);
			for (tm in deps) {
				final r = emitModule(tm, false);
				for (f in r.files) emittedModulePaths.push(f);
			}
			final rr = emitModule(typedModules[0], true);
			for (f in rr.files) emittedModulePaths.push(f);
			rootMainPath = rr.rootMain;

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
							sys.io.File.saveContent(
								shimPath,
								"(* hxhx(stage3) bootstrap shim: StringTools.hex *)\n"
								+ "\n"
								+ "let hex (n : int) (digits : int) : string =\n"
								+ "  let hexChars = \"0123456789ABCDEF\" in\n"
								+ "  let n32 = Int32.of_int n in\n"
								+ "  let rec build (x : Int32.t) (acc : string) : string =\n"
								+ "    let digit = Int32.to_int (Int32.logand x 0xFl) in\n"
								+ "    let acc2 = (String.make 1 hexChars.[digit]) ^ acc in\n"
								+ "    let x2 = Int32.shift_right_logical x 4 in\n"
								+ "    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2\n"
								+ "  in\n"
								+ "  let s = build n32 \"\" in\n"
								+ "  if digits <= 0 then s else\n"
								+ "    let rec pad (s0 : string) : string =\n"
								+ "      if String.length s0 < digits then pad (\"0\" ^ s0) else s0\n"
								+ "    in\n"
								+ "    pad s\n"
							);
						}
					} else {
						sys.io.File.saveContent(
							shimPath,
							"(* hxhx(stage3) bootstrap shim: StringTools.hex *)\n"
							+ "\n"
							+ "let hex (n : int) (digits : int) : string =\n"
							+ "  let hexChars = \"0123456789ABCDEF\" in\n"
							+ "  let n32 = Int32.of_int n in\n"
							+ "  let rec build (x : Int32.t) (acc : string) : string =\n"
							+ "    let digit = Int32.to_int (Int32.logand x 0xFl) in\n"
							+ "    let acc2 = (String.make 1 hexChars.[digit]) ^ acc in\n"
							+ "    let x2 = Int32.shift_right_logical x 4 in\n"
							+ "    if Int32.compare x2 0l = 0 then acc2 else build x2 acc2\n"
							+ "  in\n"
							+ "  let s = build n32 \"\" in\n"
							+ "  if digits <= 0 then s else\n"
							+ "    let rec pad (s0 : string) : string =\n"
							+ "      if String.length s0 < digits then pad (\"0\" ^ s0) else s0\n"
							+ "    in\n"
							+ "    pad s\n"
						);
						generatedPaths.push(shimFile);
					}
					} catch (_:Dynamic) {}
				}

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
							final hasParse =
								StringTools.startsWith(trimmed, "let parse")
								|| StringTools.startsWith(trimmed, "let rec parse")
								|| contents.indexOf("\nlet parse") != -1
								|| contents.indexOf("\nlet rec parse") != -1;
							if (!hasParse) {
								sys.io.File.saveContent(shimPath, contents + "\n\nlet parse = (Obj.magic 0)\n");
							}
						} else {
							sys.io.File.saveContent(
								shimPath,
								"(* hxhx(stage3) bootstrap shim: haxe.xml.Parser.parse *)\n"
								+ "[@@@warning \"-21-26\"]\n"
								+ "let parse = (Obj.magic 0)\n"
							);
							generatedPaths.push(shimFile);
						}
					} catch (_:Dynamic) {}
				}

				// Stage 3 bring-up: upstream unit fixtures use `Xml.*` helpers (e.g. `Xml.createElement`)
				// but Stage3 typing doesn't yet guarantee an emitted provider module for `Xml`.
				//
				// Provide a minimal module so the suite can link during emit-only bring-up.
				{
					final shimName = "Xml";
					final shimFile = shimName + ".ml";
					final shimPath = haxe.io.Path.join([outAbs, shimFile]);
					if (!sys.FileSystem.exists(shimPath)) {
						sys.io.File.saveContent(
							shimPath,
							"(* hxhx(stage3) bootstrap shim: Xml helpers *)\n"
							+ "[@@@warning \"-21-26\"]\n"
							+ "let createElement = (Obj.magic 0)\n"
							+ "let createPCData = (Obj.magic 0)\n"
							+ "let createCData = (Obj.magic 0)\n"
							+ "let createDocType = (Obj.magic 0)\n"
							+ "let createProcessingInstruction = (Obj.magic 0)\n"
							+ "let createComment = (Obj.magic 0)\n"
						);
						generatedPaths.push(shimFile);
					}
				}

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
					sys.io.File.saveContent(
						shimPath,
						"(* hxhx(stage3) bootstrap import shim: CallStack = haxe.CallStack *)\n"
						+ "include Haxe_CallStack\n"
					);
					generatedPaths.push(shimFile);
				}
			}

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
				inline function baseModuleName(path:String):String {
					final file = haxe.io.Path.withoutDirectory(path);
					return StringTools.endsWith(file, ".ml") ? file.substr(0, file.length - 3) : file;
				}

				final existing:Map<String, Bool> = new Map();
				for (p in runtimePaths) existing.set(baseModuleName(p), true);
				for (p in generatedPaths) existing.set(baseModuleName(p), true);
				for (p in emittedModulePaths) existing.set(baseModuleName(p), true);

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
				]) deny.set(m, true);

				final aliasByShort:Map<String, String> = new Map();
				for (tm in typedModules) {
					for (rawImport in tm.getEnv().getImports()) {
						if (rawImport == null) continue;
						final imp = StringTools.trim(rawImport);
						if (imp.length == 0) continue;
						if (StringTools.endsWith(imp, ".*")) continue;
						final parts = imp.split(".");
						if (parts.length == 0) continue;
						final short = parts[parts.length - 1];
						if (short == null || short.length == 0 || !isUpperStart(short)) continue;
						if (deny.exists(short)) continue;
						if (existing.exists(short)) continue;
						final target = ocamlModuleNameFromTypePath(imp);
						if (target == null || target.length == 0) continue;
						if (target == short) continue;
						// Only alias to a provider that actually exists in this build output.
						//
						// Why
						// - Some imports are inactive after conditional compilation, or are otherwise not
						//   present in the resolved+emitted module set during bring-up.
						// - Emitting an alias to a missing provider turns an unused import into a hard
						//   OCaml build failure.
						if (!existing.exists(target)) continue;
						if (!aliasByShort.exists(short)) aliasByShort.set(short, target);
					}
				}

				for (short in aliasByShort.keys()) {
					final target = aliasByShort.get(short);
					if (target == null || target.length == 0) continue;
					final aliasFile = short + ".ml";
					final aliasPath = haxe.io.Path.join([outAbs, aliasFile]);
					if (sys.FileSystem.exists(aliasPath)) continue;
					sys.io.File.saveContent(
						aliasPath,
						"(* hxhx(stage3) bootstrap import shim: " + short + " = " + target + " *)\n"
						+ "include " + target + "\n"
					);
					generatedPaths.push(aliasFile);
					existing.set(short, true);
				}
			}

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
					if (relPath == null || relPath.length == 0) return;
					final key = lowerKey(relPath);
					if (canonicalByLower.exists(key)) {
						final prev = canonicalByLower.get(key);
						// If we ever hit this on a case-sensitive filesystem, it means the build output is not
						// portable to case-insensitive hosts (two distinct units collide by case-folding).
						if (prev != relPath) throw "stage3 emitter: case-insensitive .ml collision: '" + prev + "' vs '" + relPath + "'";
						return;
					}
					canonicalByLower.set(key, relPath);
				}
				function scanMlDir(absDir:String, prefix:String):Void {
					if (absDir == null || absDir.length == 0) return;
					if (!sys.FileSystem.exists(absDir) || !sys.FileSystem.isDirectory(absDir)) return;
					for (name in sys.FileSystem.readDirectory(absDir)) {
						if (name == null || !StringTools.endsWith(name, ".ml")) continue;
						registerCanonical(prefix.length == 0 ? name : (prefix + "/" + name));
					}
				}
				scanMlDir(outAbs, "");
				scanMlDir(haxe.io.Path.join([outAbs, "runtime"]), "runtime");
				function canonicalize(relPath:String):String {
					if (relPath == null || relPath.length == 0) return relPath;
					final key = lowerKey(relPath);
					return canonicalByLower.exists(key) ? canonicalByLower.get(key) : relPath;
				}
				function uniqCaseInsensitive(xs:Array<String>):Array<String> {
					if (xs == null || xs.length <= 1) return xs;
					final seen:Map<String, Bool> = new Map();
					final out = new Array<String>();
					for (x in xs) {
						if (x == null || x.length == 0) continue;
						final key = lowerKey(x);
						if (seen.exists(key)) continue;
						seen.set(key, true);
						out.push(canonicalize(x));
					}
					return out;
				}

				final allMl = uniqCaseInsensitive(runtimePaths.concat(generatedPaths).concat(emittedModulePaths).map(canonicalize));
				final orderedMl = uniqCaseInsensitive(ocamldepSort(allMl).map(canonicalize));
				final orderedNoRoot = new Array<String>();
				final rootName = rootMainPath;
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
