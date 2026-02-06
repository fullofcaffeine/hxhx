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
	- Delta is by field name only. Modifications to existing fields are ignored in this rung.
	- If a build macro does not call `Context.getBuildFields()`, we cannot compute a delta, so we emit nothing.
**/
class BuildMacroSupport {
	static function escapeHaxeString(s:String):String {
		if (s == null) return "";
		return s
			.split("\\").join("\\\\")
			.split("\"").join("\\\"")
			.split("\n").join("\\n")
			.split("\r").join("\\r")
			.split("\t").join("\\t");
	}

	static function tryExtractTraceString(e:Null<Expr>):Null<String> {
		if (e == null) return null;
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
		  - no args
		  - body being a single `trace("...")` (directly or wrapped in a 1-statement block)
		- Emits a `public/private static` function with `:Void`.

		Non-goals (current rung)
		- Printing arbitrary expressions, types, arguments, metadata, properties, etc.
	**/
	static function printFieldMinimal(f:Field):Null<String> {
		if (f == null || f.name == null || f.name.length == 0) return null;

		final isStatic = f.access != null && f.access.indexOf(AStatic) != -1;
		final isPublic = f.access != null && f.access.indexOf(APublic) != -1;
		final vis = isPublic ? "public" : "private";
		final stat = isStatic ? " static" : "";

		return switch (f.kind) {
			case FFun(fn):
				final msg = tryExtractTraceString(fn == null ? null : fn.expr);
				final body = (msg == null)
					? "{}"
					: "{ trace(\"" + escapeHaxeString(msg) + "\"); }";
				vis + stat + " function " + f.name + "():Void " + body;
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
		final newFields = new Array<Field>();

		for (raw in arr) {
			if (raw == null) continue;
			if (!Reflect.hasField(raw, "name") || !Reflect.hasField(raw, "kind")) continue;
			final f:Field = cast raw;
			if (f == null || f.name == null || f.name.length == 0) continue;

			if (MacroRuntime.hasCurrentBuildFieldName(f.name)) continue;
			newFields.push(f);
		}

		if (newFields.length == 0) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}

		final lines = new Array<String>();
		for (f in newFields) {
			final text = printFieldMinimal(f);
			if (text != null && text.length > 0) lines.push(text);
		}

		if (lines.length == 0) {
			MacroRuntime.clearCurrentBuildFieldSnapshot();
			return;
		}

		Compiler.emitBuildFields(modulePath, lines.join("\n"));
		MacroRuntime.clearCurrentBuildFieldSnapshot();
	}
}
