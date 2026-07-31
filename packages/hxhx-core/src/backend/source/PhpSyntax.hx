package backend.source;

/**
	Deterministic PHP source fragments that depend only on explicit inputs.

	This module owns target syntax, not Haxe semantics. It retains no compiler
	or request state, so callers can use the same operations in direct and
	long-lived server compilations without an implicit active render session.
**/
class PhpSyntax {
	/**
		Quotes one PHP double-quoted string literal.

		In addition to the ordinary escaped characters, dollar signs are escaped
		so PHP cannot interpret Haxe string contents as variable interpolation.
	**/
	public static function quoteString(value:String):String {
		var text = value == null ? "" : value;
		text = StringTools.replace(text, "\\", "\\\\");
		text = StringTools.replace(text, "\"", "\\\"");
		text = StringTools.replace(text, "\n", "\\n");
		text = StringTools.replace(text, "\r", "\\r");
		text = StringTools.replace(text, "\t", "\\t");
		text = StringTools.replace(text, "$", "\\$");
		return "\"" + text + "\"";
	}

	/** Formats one string-keyed PHP associative-array entry. **/
	public static function assocEntry(key:String, valueExpr:String):String {
		return quoteString(key) + " => " + valueExpr;
	}

	/**
		Returns a sorted copy of pre-rendered associative-array entries.

		The input is left unchanged. Lexical ordering makes generated source
		independent of map traversal order.
	**/
	public static function sortedAssocEntries(entries:Array<String>):Array<String> {
		final sorted = entries.copy();
		sorted.sort(function(left, right) return left < right ? -1 : (left > right ? 1 : 0));
		return sorted;
	}

	/** Formats a deterministic PHP associative-array expression. **/
	public static function assocArrayExpr(entries:Array<String>):String {
		return "[" + sortedAssocEntries(entries).join(", ") + "]";
	}

	/**
		Appends one deterministic static associative-map declaration.

		`lines` is the caller-owned output buffer. This helper mutates only that
		explicit buffer and retains no reference after returning.
	**/
	public static function appendStaticAssocMap(lines:Array<String>, indent:String, variableName:String, entries:Array<String>):Void {
		lines.push(indent + "static $" + variableName + " = [");
		for (entry in sortedAssocEntries(entries))
			lines.push(indent + "  " + entry + ",");
		lines.push(indent + "];");
	}
}
