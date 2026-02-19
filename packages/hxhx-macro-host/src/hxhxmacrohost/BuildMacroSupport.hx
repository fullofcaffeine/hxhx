package hxhxmacrohost;

import haxe.macro.Expr;
import hxhxmacrohost.api.Compiler;

/**
	Stage4 bring-up helper: treat `Array<Field>` return values as "build macro results".

	Why
	- Our earliest `@:build(...)` rung required build macros to explicitly call `Compiler.emitBuildFields(...)`.
	- Upstream build macros usually return `Array<haxe.macro.Expr.Field>` instead.
	- To narrow the compatibility gap without transporting full typed AST, we accept `Array<Field>` return values
	  from allowlisted entrypoints and convert *new* fields into raw member snippets.

	What
	- Detect `Array<Field>` return values.
	- Compute a shallow delta by field name against the last `Context.getBuildFields()` snapshot.
	- Emit only **new** fields back to the compiler via `Compiler.emitBuildFields(...)`.

	Gotchas
	- Replacement is by field name only. If a returned field name already exists, we treat the
	  emitted member snippet as a **replacement** for the existing member (compiler-side merge
	  removes the old by name before adding the new one).
	- Removals are not supported yet (omitting a field from the returned array does not delete it).
	- If a build macro does not call `Context.getBuildFields()`, we cannot compute a delta, so we emit nothing.
**/
class BuildMacroSupport {
	static function escapeHaxeString(s:String):String {
		if (s == null)
			return "";
		return s.split("\\")
			.join("\\\\")
			.split("\"")
			.join("\\\"")
			.split("\n")
			.join("\\n")
			.split("\r")
			.join("\\r")
			.split("\t")
			.join("\\t");
	}

	static function tryExtractTraceString(e:Null<Expr>):Null<String> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EBlock(stmts) if (stmts != null && stmts.length == 1):
				tryExtractTraceString(stmts[0]);
			case ECall(target, params):
				switch (target.expr) {
					case EConst(CIdent("trace")):
						if (params != null && params.length == 1) {
							switch (params[0].expr) {
								case EConst(CString(s, _)):
									s;
								case _:
									null;
							}
						} else null;
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static function tryExtractReturnString(e:Null<Expr>):Null<String> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EBlock(stmts) if (stmts != null && stmts.length == 1):
				tryExtractReturnString(stmts[0]);
			case EReturn(v):
				if (v == null) null else switch (v.expr) {
					case EConst(CString(s, _)):
						s;
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static function tryExtractReturnInt(e:Null<Expr>):Null<Int> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EBlock(stmts) if (stmts != null && stmts.length == 1):
				tryExtractReturnInt(stmts[0]);
			case EReturn(v):
				if (v == null) null else switch (v.expr) {
					case EConst(CInt(s)):
						Std.parseInt(s);
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static function tryConstToHaxe(e:Null<Expr>):Null<String> {
		if (e == null)
			return null;
		return switch (e.expr) {
			case EConst(CString(s, _)):
				"\"" + escapeHaxeString(s) + "\"";
			case EConst(CInt(s)):
				s;
			case EConst(CFloat(s)):
				s;
			case EConst(CIdent("true")):
				"true";
			case EConst(CIdent("false")):
				"false";
			case EConst(CIdent("null")):
				"null";
			case _:
				null;
		}
	}

	/**
		Print a tiny subset of `haxe.macro.Expr.Field` values to raw Haxe member snippets.

		Why
		- Stage4 bring-up should not require compiling upstream `haxe.macro.Printer` yet.
		  `Printer` pulls in generic-heavy code that our OCaml backend does not fully support
		  at this rung.
		- We still need *some* way to turn returned fields into deterministic snippet text so
		  Stage3 can merge them via `compiler.emitBuildFields`.

		What
		- Supports only `FFun` with:
		  - non-optional args (names only; no types/defaults)
		  - body being one of:
			- a single `trace("...")` (directly or wrapped in a 1-statement block)
			- `return "<...>"` (string literal)
			- `return <int>` (int literal)
		- Supports only `FVar` as `var name:Dynamic;` (no init / no properties).
		- Emits members with `public/private` + optional `static`.

		Non-goals (current rung)
		- Printing arbitrary expressions, types, arguments, metadata, properties, etc.
	**/
	static function printFieldMinimal(f:Field):Null<String> {
		if (f == null || f.name == null || f.name.length == 0)
			return null;

		final isStatic = f.access != null && f.access.indexOf(AStatic) != -1;
		final isPublic = f.access != null && f.access.indexOf(APublic) != -1;
		final vis = isPublic ? "public" : "private";
		final stat = isStatic ? " static" : "";

		return switch (f.kind) {
			case FFun(fn):
				if (fn == null)
					return null;

				// Keep arg handling very conservative: Stage3's bootstrap parser doesn't
				// support optional args (`?x`) or default values robustly yet.
				final argNames = new Array<String>();
				if (fn.args != null) {
					for (a in fn.args) {
						if (a == null || a.name == null || a.name.length == 0)
							return null;
						if (a.opt == true)
							return null;
						argNames.push(a.name);
					}
				}

				final msg = tryExtractTraceString(fn.expr);
				if (msg != null) {
					final body = "{ trace(\"" + escapeHaxeString(msg) + "\"); }";
					return vis + stat + " function " + f.name + "(" + argNames.join(", ") + ") " + body;
				}

				final retStr = tryExtractReturnString(fn.expr);
				if (retStr != null) {
					final body = "{ return \"" + escapeHaxeString(retStr) + "\"; }";
					return vis + stat + " function " + f.name + "(" + argNames.join(", ") + ") " + body;
				}

				final retInt = tryExtractReturnInt(fn.expr);
				if (retInt != null) {
					final body = "{ return " + Std.string(retInt) + "; }";
					return vis + stat + " function " + f.name + "(" + argNames.join(", ") + ") " + body;
				}

				null;
			case FVar(_t, e):
				final init = tryConstToHaxe(e);
				if (init != null) {
					vis + stat + " var " + f.name + " = " + init + ";";
				} else {
					vis + stat + " var " + f.name + ":Dynamic;";
				}
			case _:
				null;
		}
	}

	public static function afterEntrypoint(ret:Dynamic):Void {
		if (ret == null) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}

		// If the macro didn't call `Context.getBuildFields()`, we don't know what the original field set was.
		// In this bring-up rung we avoid emitting potentially-duplicated members.
		if (!MacroRuntime.hasCurrentBuildFieldSnapshot()) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}

		final modulePath = Compiler.getDefine("HXHX_BUILD_MODULE");
		if (modulePath == null || modulePath.length == 0) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}

		var arr:Array<Dynamic> = null;
		try {
			arr = cast ret;
		} catch (_:Dynamic) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}
		if (arr == null) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}
		final emittedFields = new Array<Field>();
		final seenByName:Map<String, Bool> = new Map();

		for (raw in arr) {
			if (raw == null)
				continue;
			if (!Reflect.hasField(raw, "name") || !Reflect.hasField(raw, "kind"))
				continue;
			final f:Field = cast raw;
			if (f == null || f.name == null || f.name.length == 0)
				continue;

			if (seenByName.exists(f.name))
				continue;
			seenByName.set(f.name, true);

			// Emit both:
			// - truly new fields (name not in snapshot), and
			// - supported replacements (name already in snapshot).
			//
			// Replacement behavior is implemented compiler-side when merging emitted members.
			emittedFields.push(f);
		}

		if (emittedFields.length == 0) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}

		final lines = new Array<String>();
		for (f in emittedFields) {
			final text = printFieldMinimal(f);
			if (text != null && text.length > 0)
				lines.push(text);
		}

		if (lines.length == 0) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}

		Compiler.emitBuildFields(modulePath, lines.join("\n"));
		MacroRuntime.clearCurrentBuildFieldSnapshot();
	}
}
