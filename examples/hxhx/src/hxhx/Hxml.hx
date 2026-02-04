package hxhx;

/**
	Very small `.hxml` parser for `hxhx` Stage1.

	Why
	- Upstream `haxe` supports passing an `.hxml` build file as a positional argument.
	- For the Stage1 bring-up path (`--hxhx-stage1`), we want deterministic runs that
	  look like "real" invocations, without delegating to stage0.
	- Parsing a small `.hxml` subset is a high-leverage step toward upstream gates.

	What
	- Parses a file into a flat argv-style list.
	- Supports:
	  - blank lines
	  - `#` comments (at start of line, or after whitespace)
	  - one or more tokens per line (e.g. `-main Main`)
	  - basic quoting with `'...'` / `"..."` (to allow paths with spaces)
	- Explicitly rejects `--next`/`--each` for now (multi-unit `.hxml` is a later stage).

	How
	- We tokenize each line with a tiny state machine (quote/no-quote + backslash escapes),
	  then concatenate the resulting tokens.

	Notes
	- This is intentionally not a full reimplementation of upstream `hxml` parsing.
	  As Stage1 grows, we can extend this to match upstream behavior more closely.
**/
class Hxml {
	public static function parseFile(path:String):Null<Array<String>> {
		final content = try sys.io.File.getContent(path) catch (_:Dynamic) null;
		if (content == null) {
			Sys.println("hxhx(stage1): failed to read hxml: " + path);
			return null;
		}
		final out = new Array<String>();
		final lines = content.split("\n");
		for (ln in lines) {
			final tokens = tokenizeLine(ln);
			if (tokens == null) return null;
			for (t in tokens) {
				if (t == "--next" || t == "--each") {
					Sys.println("hxhx(stage1): unsupported hxml directive: " + t);
					return null;
				}
				out.push(t);
			}
		}
		return out;
	}

	static function isSpace(c:Int):Bool {
		return c == " ".code || c == "\t".code || c == "\r".code;
	}

	static function tokenizeLine(line:String):Null<Array<String>> {
		if (line == null) return [];
		final s = line;
		var i = 0;

		// Trim leading whitespace.
		while (i < s.length && isSpace(s.charCodeAt(i))) i++;
		if (i >= s.length) return [];
		if (s.charCodeAt(i) == "#".code) return [];

		final tokens = new Array<String>();
		var cur = new StringBuf();
		var quote:Int = 0; // 0 = none, otherwise quote char code

		inline function flush():Void {
			if (cur.length > 0) {
				tokens.push(cur.toString());
				cur = new StringBuf();
			}
		}

		while (i < s.length) {
			final c = s.charCodeAt(i);

			// Comment start (only when not in quotes, and preceded by whitespace).
			if (quote == 0 && c == "#".code) {
				break;
			}

			if (quote == 0 && isSpace(c)) {
				flush();
				while (i < s.length && isSpace(s.charCodeAt(i))) i++;
				continue;
			}

			if (quote == 0 && (c == "\"".code || c == "'".code)) {
				quote = c;
				i++;
				continue;
			}

			if (quote != 0 && c == quote) {
				quote = 0;
				i++;
				continue;
			}

			if (c == "\\".code && i + 1 < s.length) {
				final n = s.charCodeAt(i + 1);
				switch (n) {
					case "n".code:
						cur.addChar("\n".code);
						i += 2;
						continue;
					case "r".code:
						cur.addChar("\r".code);
						i += 2;
						continue;
					case "t".code:
						cur.addChar("\t".code);
						i += 2;
						continue;
					case "\\".code, "\"".code, "'".code, "#".code:
						cur.addChar(n);
						i += 2;
						continue;
					case _:
				}
			}

			cur.addChar(c);
			i++;
		}

		if (quote != 0) {
			Sys.println("hxhx(stage1): unterminated quote in hxml line: " + line);
			return null;
		}

		flush();
		return tokens;
	}
}

