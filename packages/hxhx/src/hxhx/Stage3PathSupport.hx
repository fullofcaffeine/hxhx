package hxhx;

import haxe.io.Path;

/**
	Stage3 path normalization and root inference helpers.

	Why
	- `Stage3Compiler` still owned cwd/path normalization plus the small heuristics
	  that infer resolver roots for macro-only and display-style invocations.
	- Those helpers are request-shaping support logic, not main driver orchestration.

	What
	- Normalizes relative paths against a Stage3 cwd.
	- Infers a root type from a macro expression.
	- Infers a root type from a `--display <file@mode>` request.

	How
	- Preserve the existing path resolution and fallback behavior exactly.
	- Keep the helper surface narrow and Stage3-specific.
**/
class Stage3PathSupport {
	public static function absFromCwd(cwd:String, path:String):String {
		if (path == null || path.length == 0)
			return cwd;
		return Path.isAbsolute(path) ? Path.normalize(path) : Path.normalize(Path.join([cwd, path]));
	}

	public static function inferMainFromMacroExpr(expr:String):String {
		if (expr == null)
			return "";
		var value = StringTools.trim(expr);
		if (value.length == 0)
			return "";
		final paren = value.indexOf("(");
		if (paren != -1)
			value = StringTools.trim(value.substr(0, paren));
		final lastDot = value.lastIndexOf(".");
		if (lastDot == -1)
			return value;
		return StringTools.trim(value.substr(0, lastDot));
	}

	#if !hxhx_stage0_no_display
	public static function inferMainFromDisplayRequest(displayRequest:String, classPaths:Array<String>, cwd:String):String {
		if (displayRequest == null)
			return "";
		final trimmed = StringTools.trim(displayRequest);
		if (trimmed.length == 0)
			return "";

		final at = trimmed.indexOf("@");
		final rawPath = at == -1 ? trimmed : trimmed.substr(0, at);
		if (rawPath.length == 0 || !StringTools.endsWith(rawPath, ".hx"))
			return "";

		final displayAbs = absFromCwd(cwd, rawPath);
		final displayNorm = Path.normalize(displayAbs);

		for (cp in classPaths) {
			final cpAbs = absFromCwd(cwd, cp);
			var cpNorm = Path.normalize(cpAbs);
			if (!StringTools.endsWith(cpNorm, "/"))
				cpNorm += "/";
			if (!StringTools.startsWith(displayNorm, cpNorm))
				continue;
			var rel = displayNorm.substr(cpNorm.length);
			if (StringTools.endsWith(rel, ".hx"))
				rel = rel.substr(0, rel.length - 3);
			rel = StringTools.replace(rel, "\\", "/");
			rel = StringTools.replace(rel, "/", ".");
			if (rel.length > 0)
				return rel;
		}

		return Path.withoutExtension(Path.withoutDirectory(displayNorm));
	}
	#end
}
