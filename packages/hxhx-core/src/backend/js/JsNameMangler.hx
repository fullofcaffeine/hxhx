package backend.js;

/**
	Deterministic JavaScript name mangling helpers.

	Why
	- Stage3 AST identifiers can include names that are invalid/reserved in JS.
	- We need stable symbol names for deterministic snapshots and reproducible behavior.
**/
class JsNameMangler {
	static function isReserved(name:String):Bool {
		return switch (name) {
			case "break" | "case" | "catch" | "class" | "const" | "continue" | "debugger" | "default" | "delete" | "do" | "else" | "enum" | "export" |
				"extends" | "false" | "finally" | "for" | "function" | "if" | "import" | "in" | "instanceof" | "new" | "null" | "return" | "super" |
				"switch" | "this" | "throw" | "true" | "try" | "typeof" | "var" | "void" | "while" | "with" | "yield" | "let" | "static" | "implements" |
				"interface" | "package" | "private" | "protected" | "public":
				true;
			case _:
				false;
		}
	}

	public static function identifier(raw:String):String {
		final s = raw == null ? "" : raw;
		final out = new StringBuf();
		for (i in 0...s.length) {
			final c = s.charCodeAt(i);
			final isAlpha = (c >= 97 && c <= 122) || (c >= 65 && c <= 90);
			final isNum = c >= 48 && c <= 57;
			final ch = isAlpha || isNum || c == 95 ? String.fromCharCode(c) : "_";
			if (i == 0 && isNum)
				out.add("_");
			out.add(ch);
		}
		var r = out.toString();
		if (r.length == 0)
			r = "_";
		if (isReserved(r))
			r += "_";
		return r;
	}

	public static function classVarName(fullName:String):String {
		return "__hx_cls_" + identifier(fullName);
	}

	public static function quoteString(raw:String):String {
		final text = raw == null ? "" : raw;
		final out = new StringBuf();
		out.add("\"");
		for (i in 0...text.length) {
			final code = text.charCodeAt(i);
			switch (code) {
				case 8:
					out.add("\\b");
				case 9:
					out.add("\\t");
				case 10:
					out.add("\\n");
				case 12:
					out.add("\\f");
				case 13:
					out.add("\\r");
				case 34:
					out.add("\\\"");
				case 92:
					out.add("\\\\");
				case _:
					if (code < 32 || code > 126) {
						out.add("\\u" + StringTools.hex(code, 4));
					} else {
						out.addChar(code);
					}
			}
		}
		out.add("\"");
		return out.toString();
	}

	public static function propertySuffix(name:String):String {
		final id = identifier(name);
		return id == name ? ("." + id) : ("[" + quoteString(name) + "]");
	}
}
