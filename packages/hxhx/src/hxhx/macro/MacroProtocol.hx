package hxhx.macro;

/**
	Stage 4 (Model A) macro host protocol helpers.

	Why
	- The macro host protocol is intentionally **target-agnostic**: it is line-based and uses
	  length-prefixed payload fragments.
	- Keeping the encoding/decoding logic in Haxe means:
	  - the compiler core stays ~99% Haxe,
	  - other future host targets (Rust/C++ builds of `hxhx`) can reuse the same protocol code.

	What
	- Escape/unescape for payload text.
	- `encodeLen` / `decodeLenValue` helpers for `<k>=<len>:<payload>`.
	- `splitN` for parsing structured lines with a tail field.
	- `kvGet` for extracting length-prefixed values from a tail string.
**/
class MacroProtocol {
	public static function escapePayload(s:String):String {
		if (s == null) return "";
		return s
			.split("\\").join("\\\\")
			.split("\n").join("\\n")
			.split("\r").join("\\r")
			.split("\t").join("\\t");
	}

	public static function unescapePayload(s:String):String {
		if (s == null || s.length == 0) return "";
		final out = new StringBuf();
		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c == "\\".code && i + 1 < s.length) {
				final n = s.charCodeAt(i + 1);
				switch (n) {
					case "n".code: out.addChar("\n".code);
					case "r".code: out.addChar("\r".code);
					case "t".code: out.addChar("\t".code);
					case "\\".code: out.addChar("\\".code);
					case _: out.addChar(n);
				}
				i += 2;
				continue;
			}
			out.addChar(c);
			i++;
		}
		return out.toString();
	}

	public static function encodeLen(label:String, value:String):String {
		final enc = escapePayload(value);
		return label + "=" + enc.length + ":" + enc;
	}

	public static function decodeLenValue(part:String):String {
		final eq = part.indexOf("=");
		if (eq <= 0) return "";
		final rest = part.substr(eq + 1);
		final colon = rest.indexOf(":");
		if (colon <= 0) return "";
		final len = Std.parseInt(rest.substr(0, colon));
		if (len == null || len < 0) return "";
		final payload = rest.substr(colon + 1);
		if (payload.length < len) return "";
		return unescapePayload(payload.substr(0, len));
	}

	/**
		Parse a tail that contains one or more `key=<len>:<payload>` fragments.

		Why
		- The macro host protocol uses length prefixes so payloads can contain spaces.
		- We therefore cannot reliably parse by splitting on spaces.

		What
		- Returns a map from key → decoded payload string.
	**/
	public static function kvParse(tail:String):Map<String, String> {
		final out:Map<String, String> = [];
		if (tail == null || tail.length == 0) return out;
		var i = 0;
		inline function isSpace(c:Int):Bool return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code;
		inline function isDigit(c:Int):Bool return c >= "0".code && c <= "9".code;
		while (i < tail.length) {
			while (i < tail.length && isSpace(tail.charCodeAt(i))) i++;
			if (i >= tail.length) break;

			final keyStart = i;
			while (i < tail.length) {
				final c = tail.charCodeAt(i);
				if (c == "=".code || isSpace(c)) break;
				i++;
			}
			if (i >= tail.length || tail.charCodeAt(i) != "=".code) {
				while (i < tail.length && !isSpace(tail.charCodeAt(i))) i++;
				continue;
			}
			final key = tail.substr(keyStart, i - keyStart);
			i++; // '='

			final lenStart = i;
			while (i < tail.length && isDigit(tail.charCodeAt(i))) i++;
			if (i >= tail.length || tail.charCodeAt(i) != ":".code) {
				while (i < tail.length && !isSpace(tail.charCodeAt(i))) i++;
				continue;
			}
			final lenStr = tail.substr(lenStart, i - lenStart);
			final len = Std.parseInt(lenStr);
			i++; // ':'
			if (len == null || len < 0 || i + len > tail.length) break;

			final enc = tail.substr(i, len);
			i += len;
			out.set(key, unescapePayload(enc));
		}
		return out;
	}

	public static function splitN(s:String, n:Int):Array<String> {
		final head = new Array<String>();
		var i = 0;
		var start = 0;
		while (head.length < n && i <= s.length) {
			if (i == s.length || s.charCodeAt(i) == " ".code) {
				if (i > start) head.push(s.substr(start, i - start));
				while (i < s.length && s.charCodeAt(i) == " ".code) i++;
				start = i;
				continue;
			}
			i++;
		}
		while (head.length < n) head.push("");
		final tail = start <= s.length ? s.substr(start) : "";
		head.push(tail);
		return head;
	}

	public static function kvGet(tail:String, key:String):String {
		final m = kvParse(tail);
		return m.exists(key) ? m.get(key) : "";
	}
}
