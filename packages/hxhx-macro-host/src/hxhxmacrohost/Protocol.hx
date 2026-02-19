package hxhxmacrohost;

/**
	Line-based RPC protocol for the Stage 4 macro-host skeleton.

	Why
	- Stage 4 (“native macro execution”) needs an explicit ABI boundary between:
	  - the compiler core (`hxhx`)
	  - the macro runtime (“macro host”)
	- Model A (recommended first) runs the macro runtime out-of-process and talks
	  over a **versioned** protocol. This keeps the compiler isolated from macro
	  crashes and avoids OCaml dynlink complexities during bring-up.

	What
	- This file defines the minimal, *human-readable* protocol used by:
	  - `packages/hxhx-macro-host` (server)
	  - `packages/hxhx` (client; `hxhx.macro.MacroHostClient`)
	- The protocol is intentionally simple and stable:
	  - single-line records
	  - request IDs for correlation
	  - length-prefixed payload fragments for safe transport of arbitrary strings

	How
	- Handshake:
	  - Server prints: `hxhx_macro_rpc_v=1`
	  - Client replies: `hello proto=1`
	  - Server replies: `ok`
	- Requests:
	  - `req <id> <method> <payload...>`
	- Responses:
	  - `res <id> ok <payload...>`
	  - `res <id> err <payload...>`

	We use a minimal length-prefixed encoding for payload fragments:

	- `n=<len>:<escaped>`
	- `v=<len>:<escaped>`
	- `m=<len>:<escaped>` (error message)
	- `p=<len>:<escaped>` (error position; currently `file:line`)

	Escaping:
	- `\\n`, `\\r`, `\\t`, `\\\\` are supported (best-effort).

	This is a skeleton ABI: later stages will add structured encodings for:
	- positions
	- macro AST
	- typed types/fields
**/
class Protocol {
	public static inline final VERSION:Int = 1;
	public static inline final SERVER_BANNER:String = "hxhx_macro_rpc_v=" + VERSION;

	public static function escapePayload(s:String):String {
		if (s == null)
			return "";
		return s.split("\\")
			.join("\\\\")
			.split("\n")
			.join("\\n")
			.split("\r")
			.join("\\r")
			.split("\t")
			.join("\\t");
	}

	public static function unescapePayload(s:String):String {
		if (s == null || s.length == 0)
			return "";
		final out = new StringBuf();
		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c == "\\".code && i + 1 < s.length) {
				final n = s.charCodeAt(i + 1);
				switch (n) {
					case "n".code:
						out.addChar("\n".code);
					case "r".code:
						out.addChar("\r".code);
					case "t".code:
						out.addChar("\t".code);
					case "\\".code:
						out.addChar("\\".code);
					case _:
						out.addChar(n);
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
		// part is `<label>=<len>:<payload...>` (payload may contain escaped sequences)
		final eq = part.indexOf("=");
		if (eq <= 0)
			return "";
		final rest = part.substr(eq + 1);
		final colon = rest.indexOf(":");
		if (colon <= 0)
			return "";
		final len = Std.parseInt(rest.substr(0, colon));
		if (len == null || len < 0)
			return "";
		final payload = rest.substr(colon + 1);
		if (payload.length < len)
			return "";
		return unescapePayload(payload.substr(0, len));
	}

	/**
		Parse a tail string that contains one or more `key=<len>:<payload...>` fragments.

		Why
		- Earlier bring-up code used `tail.split(" ")`, which breaks as soon as the
		  encoded payload contains spaces.
		- Using the `<len>` prefix lets us scan deterministically without ambiguous
		  delimiters.

		What
		- Returns a map from key → decoded payload string.
	**/
	public static function kvParse(tail:String):Map<String, String> {
		final out:Map<String, String> = [];
		if (tail == null || tail.length == 0)
			return out;
		var i = 0;
		inline function isSpace(c:Int):Bool
			return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code;
		inline function isDigit(c:Int):Bool
			return c >= "0".code && c <= "9".code;
		while (i < tail.length) {
			while (i < tail.length && isSpace(tail.charCodeAt(i)))
				i++;
			if (i >= tail.length)
				break;

			final keyStart = i;
			while (i < tail.length) {
				final c = tail.charCodeAt(i);
				if (c == "=".code || isSpace(c))
					break;
				i++;
			}
			if (i >= tail.length || tail.charCodeAt(i) != "=".code) {
				while (i < tail.length && !isSpace(tail.charCodeAt(i)))
					i++;
				continue;
			}
			final key = tail.substr(keyStart, i - keyStart);
			i++; // '='

			final lenStart = i;
			while (i < tail.length && isDigit(tail.charCodeAt(i)))
				i++;
			if (i >= tail.length || tail.charCodeAt(i) != ":".code) {
				while (i < tail.length && !isSpace(tail.charCodeAt(i)))
					i++;
				continue;
			}
			final lenStr = tail.substr(lenStart, i - lenStart);
			final len = Std.parseInt(lenStr);
			i++; // ':'
			if (len == null || len < 0 || i + len > tail.length)
				break;

			final enc = tail.substr(i, len);
			i += len;
			out.set(key, unescapePayload(enc));
		}
		return out;
	}

	public static function kvGet(tail:String, key:String):String {
		final m = kvParse(tail);
		return m.exists(key) ? m.get(key) : "";
	}

	public static function splitN(s:String, n:Int):Array<String> {
		// Split into exactly `n` space-separated fields, plus a final "tail" field (may contain spaces).
		final head = new Array<String>();
		var i = 0;
		var start = 0;
		while (head.length < n && i <= s.length) {
			if (i == s.length || s.charCodeAt(i) == " ".code) {
				if (i > start)
					head.push(s.substr(start, i - start));
				while (i < s.length && s.charCodeAt(i) == " ".code)
					i++;
				start = i;
				continue;
			}
			i++;
		}
		while (head.length < n)
			head.push("");
		final tail = start <= s.length ? s.substr(start) : "";
		head.push(tail);
		return head;
	}
}
