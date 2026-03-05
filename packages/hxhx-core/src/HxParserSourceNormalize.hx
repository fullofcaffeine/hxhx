/**
	Parser text-repair helpers for native frontend expression payloads.

	Why
	- `HxParser` is one of the largest compile units in this repo and a frequent hotspot in
	  stage0 memory probes.
	- We keep behavior-preserving helper extraction incremental: move leaf text-normalization
	  routines out of `HxParser` so the parser core and repair logic can evolve independently.

	What
	- Normalizes dense escaped quotes (`"""` -> `"\\\""`) in expression payloads.
	- Repairs compacted keyword spacing for `new` constructor forms (`newjs.Foo` -> `new js.Foo`).

	How
	- These functions are pure text transforms and preserve existing `HxParser` behavior.
**/
class HxParserSourceNormalize {
	/**
		Normalize dense escaped quotes and compacted keyword spacing.
	**/
	public static function normalizeDenseEscapedQuotes(source:String):String {
		// Native protocol expression payloads can occasionally arrive with escaped quote
		// strings compacted to `"""` (for `"\\""`) when whitespace is stripped.
		//
		// Example:
		//   [" ".code, ... , """.code, ...]
		//
		// Without this normalization, `readString` sees the first two quotes as an empty
		// string and then fails with an unterminated literal on the third quote.
		if (source == null || source.length == 0)
			return source;
		var normalized = source;
		if (normalized.indexOf('"""') != -1) {
			final q = '"';
			final triple = q + q + q;
			final escapedQuoteString = q + "\\" + q + q;
			normalized = StringTools.replace(normalized, triple, escapedQuoteString);
		}
		normalized = normalizeDenseKeywordSpacing(normalized);
		return normalized;
	}

	/**
		Repair compacted keyword spacing in native payload expression slices.

		Why
		- Native payload emitters can compact spaces in expression snippets.
		- Constructor forms like `new js.lib.DataView(...)` can arrive as
		  `newjs.lib.DataView(...)`.
		- Without spacing repair, the lexer reads `newjs` as an identifier and we lose
		  constructor semantics (`ENew`), which later emits invalid JS (`newjs.*`).
	**/
	public static function normalizeDenseKeywordSpacing(source:String):String {
		if (source == null || source.length == 0)
			return source;
		final compactNewExpr = ~/(^|[^A-Za-z0-9_])new([A-Za-z_])/g;
		return compactNewExpr.map(source, function(re:EReg):String {
			return re.matched(1) + "new " + re.matched(2);
		});
	}
}
