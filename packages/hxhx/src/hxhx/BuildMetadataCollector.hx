package hxhx;

import hxhx.macro.MacroState;

/**
	Collects source-local and registered global `@:build(...)` / `@:autoBuild(...)` expressions.

	Why
	- `Stage3Compiler` needs this logic during Stage4 bring-up, but the logic itself is small and
	  does not depend on the rest of the Stage3 orchestration surface.
	- Keeping it in a focused helper avoids pulling the entire Stage3 compiler into small tests and
	  utility code that only needs metadata collection.

	What
	- Scans raw source text for `@:build(...)` / `@:autoBuild(...)` expressions before the first
	  `class` keyword.
	- Appends matching registered global metadata rules from `MacroState`.
	- Deduplicates exact expression strings while preserving encounter order.
**/
class BuildMetadataCollector {
	/**
		Extract raw build-macro expressions from source metadata.
	**/
	public static function findBuildMacroExprs(source:String):Array<String> {
		final out = new Array<String>();
		if (source == null || source.length == 0)
			return out;

		final lex = new HxLexer(source);
		var t = lex.next();

		while (true) {
			switch (t.getKind()) {
				case TEof:
					return out;
				case TKeyword(KClass):
					return out;
				case TOther(code) if (code == "@".code):
					final t2 = lex.next();
					final t3 = lex.next();
					final t4 = lex.next();

					final isMeta = switch ([t2.getKind(), t3.getKind(), t4.getKind()]) {
						case [TColon, TIdent("build"), TLParen]: true;
						case [TColon, TIdent("autoBuild"), TLParen]: true;
						case _: false;
					}
					if (!isMeta) {
						t = lex.next();
						continue;
					}

					var depth = 1;
					final startIndex = t4.getPos().getIndex() + 1;
					var endIndex = startIndex;
					var inner = lex.next();
					while (true) {
						switch (inner.getKind()) {
							case TEof:
								endIndex = source.length;
								break;
							case TLParen:
								depth += 1;
							case TRParen:
								depth -= 1;
								if (depth == 0) {
									endIndex = inner.getPos().getIndex();
									break;
								}
							case _:
						}
						inner = lex.next();
					}

					final expr = trim(source.substring(startIndex, endIndex));
					if (expr.length > 0)
						out.push(expr);

					t = lex.next();
					continue;
				case _:
			}

			t = lex.next();
		}

		return out;
	}

	/**
		Collect every build-macro expression that applies to `modulePath`.
	**/
	public static function collectBuildMacroExprs(source:String, modulePath:String):Array<String> {
		final out = new Array<String>();
		final seen:Map<String, Bool> = new Map();

		inline function addExpr(expr:String):Void {
			if (expr == null)
				return;
			final normalized = trim(expr);
			if (normalized.length == 0 || seen.exists(normalized))
				return;
			seen.set(normalized, true);
			out.push(normalized);
		}

		for (expr in findBuildMacroExprs(source))
			addExpr(expr);

		for (rule in MacroState.listGlobalMetadataRules()) {
			if (!rule.toTypes)
				continue;
			if (!matchesMetadataPathFilter(modulePath, rule.pathFilter, rule.recursive))
				continue;
			for (expr in findBuildMacroExprs(rule.metadata))
				addExpr(expr);
		}

		return out;
	}

	public static function matchesMetadataPathFilter(modulePath:String, pathFilter:String, recursive:Bool):Bool {
		final moduleName = modulePath == null ? "" : trim(modulePath);
		final filter = pathFilter == null ? "" : trim(pathFilter);
		if (moduleName.length == 0)
			return false;
		if (filter.length == 0)
			return true;
		if (recursive)
			return moduleName == filter || StringTools.startsWith(moduleName, filter + ".");
		return moduleName == filter;
	}

	static inline function trim(value:String):String {
		return value == null ? "" : StringTools.trim(value);
	}
}
