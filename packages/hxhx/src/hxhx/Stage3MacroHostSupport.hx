package hxhx;

import haxe.io.Eof;
import haxe.io.Path;
import hxhx.runtime.NullableRuntimeString;

/**
	Stage3 macro expression allowlist and macro-host auto-build helpers.

	Why
	- `Stage3Compiler` still owned parsing of `HXHX_EXPR_MACROS`, builtin macro
	  filtering, and the stage0-backed macro-host auto-build wrapper.
	- Those pieces are macro-host support glue, not core driver orchestration.

	What
	- Parses delimited macro expression lists from env-style strings.
	- Merges builtin expression macro allowlists.
	- Detects builtin macro expressions and whether auto-build is enabled.
	- Builds the external macro host via the repo script and returns the exe path.

	How
	- Preserve the current env var names, script contract, and filtering rules.
	- Keep the helper surface intentionally narrow and Stage3-specific.
**/
class Stage3MacroHostSupport {
	static inline function trim(value:String):String {
		return NullableRuntimeString.trimToEmpty(value);
	}

	public static function parseDelimitedList(raw:String):Array<String> {
		final out = new Array<String>();
		final normalized = NullableRuntimeString.normalize(raw);
		if (normalized == null)
			return out;
		final value = StringTools.trim(normalized);
		if (value.length == 0)
			return out;

		final parts = value.indexOf(";") != -1 ? value.split(";") : value.split(",");
		for (part in parts) {
			if (part == null)
				continue;
			final trimmed = StringTools.trim(part);
			if (trimmed.length == 0)
				continue;
			if (out.indexOf(trimmed) == -1)
				out.push(trimmed);
		}
		return out;
	}

	static function builtinExprMacros():Array<String> {
		return ["unit.HelperMacros.getCompilationDate()", "HelperMacros.getCompilationDate()"];
	}

	public static function exprMacroAllowlistFromEnv():Array<String> {
		final out = new Array<String>();
		for (expr in builtinExprMacros())
			if (out.indexOf(expr) == -1)
				out.push(expr);
		for (expr in parseDelimitedList(Sys.getEnv("HXHX_EXPR_MACROS")))
			if (expr != null && expr.length > 0 && out.indexOf(expr) == -1)
				out.push(expr);
		return out;
	}

	public static function isBuiltinMacroExpr(expr:String):Bool {
		final value = trim(expr);
		return StringTools.startsWith(value, "BuiltinMacros.")
			|| StringTools.startsWith(value, "hxhxmacrohost.BuiltinMacros.")
			|| StringTools.startsWith(value, "hxhxmacrohost.BuiltinMacros")
			|| StringTools.startsWith(value, "nullSafety(")
			|| StringTools.startsWith(value, "Validator.register(");
	}

	public static function anyNonBuiltinMacro(exprs:Array<String>):Bool {
		for (expr in exprs)
			if (!isBuiltinMacroExpr(expr))
				return true;
		return false;
	}

	public static function shouldAutoBuildMacroHost():Bool {
		final value = trim(Sys.getEnv("HXHX_MACRO_HOST_AUTO_BUILD"));
		return value == "1" || value == "true" || value == "yes";
	}

	public static function buildMacroHostExe(repoRoot:String, extraCp:Array<String>, entrypoints:Array<String>):String {
		final script = Path.join([repoRoot, "scripts", "hxhx", "build-hxhx-macro-host.sh"]);
		if (!sys.FileSystem.exists(script))
			throw "missing macro host build script: " + script;

		Sys.putEnv("HXHX_MACRO_HOST_EXTRA_CP", (extraCp != null && extraCp.length > 0) ? extraCp.join(":") : "");
		Sys.putEnv("HXHX_MACRO_HOST_ENTRYPOINTS", (entrypoints != null && entrypoints.length > 0) ? entrypoints.join(";") : "");

		final process = new sys.io.Process("bash", [script]);
		final lines = new Array<String>();
		try {
			while (true)
				lines.push(process.stdout.readLine());
		} catch (_:Eof) {}

		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "macro host build failed with exit code " + code;

		var exe = "";
		for (line in lines) {
			final trimmed = trim(line);
			if (trimmed.length > 0)
				exe = trimmed;
		}
		if (exe.length == 0)
			throw "macro host build produced no executable path";
		return exe;
	}
}
