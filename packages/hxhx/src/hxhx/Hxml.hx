package hxhx;

import haxe.io.Path;

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
		final seen = new Map<String, Bool>();
		return parseFileRec(Path.normalize(path), seen, 0);
	}

	static function parseFileRec(path:String, seen:Map<String, Bool>, depth:Int):Null<Array<String>> {
		if (depth > 25) {
			Sys.println("hxhx(stage1): hxml include depth exceeded: " + path);
			return null;
		}

		final norm = Path.normalize(path);
		if (seen.exists(norm)) {
			Sys.println("hxhx(stage1): hxml include cycle: " + norm);
			return null;
		}
		seen.set(norm, true);

		final content = try sys.io.File.getContent(norm) catch (_:Dynamic) null;
		if (content == null) {
			Sys.println("hxhx(stage1): failed to read hxml: " + norm);
			return null;
		}

		final fileDir0 = Path.directory(norm);
		final fileDir = (fileDir0 == null || fileDir0.length == 0) ? "." : fileDir0;

		final tokens = new Array<String>();
		final lines = content.split("\n");
		for (ln in lines) {
			final lineTokens = tokenizeLine(ln);
			if (lineTokens == null) return null;
			for (t in lineTokens) tokens.push(t);
		}

		// Rewrite relative `-cp` / `-p` entries relative to this file.
		var i = 0;
		while (i < tokens.length) {
			switch (tokens[i]) {
				case "-cp", "-p":
					if (i + 1 < tokens.length) {
						final cp = tokens[i + 1];
						if (cp != null && cp.length > 0 && !Path.isAbsolute(cp)) {
							tokens[i + 1] = Path.normalize(Path.join([fileDir, cp]));
						}
					}
					i += 2;
				case _:
					i += 1;
			}
		}

		// Expand positional `.hxml` includes (upstream uses this heavily, e.g. `compile-macro.hxml` includes `compile-each.hxml`).
		final out = new Array<String>();
		for (t in tokens) {
			if (t == "--next" || t == "--each") {
				Sys.println("hxhx(stage1): unsupported hxml directive: " + t);
				return null;
			}

			if (!StringTools.startsWith(t, "-") && StringTools.endsWith(t, ".hxml")) {
				final included = Path.isAbsolute(t) ? Path.normalize(t) : Path.normalize(Path.join([fileDir, t]));
				final expanded = parseFileRec(included, seen, depth + 1);
				if (expanded == null) return null;
				for (x in expanded) out.push(x);
				continue;
			}

			out.push(t);
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

		// Upstream `.hxml` treats some flags as "consume the rest of the line as a single argument"
		// (not whitespace-tokenized). This is especially important for:
		// - `--macro <expr>` where `<expr>` commonly contains spaces/parentheses, and
		// - `--cmd <shell>` where the command is naturally multi-word.
		//
		// Our Stage1/Stage3 bring-up uses `.hxml` heavily for upstream gates (Gate1/Gate2), so we
		// implement this small compatibility behavior here in the tokenizer (before generic splitting).
		function restOfLineAfter(prefix:String):Null<Array<String>> {
			final p = prefix.length;
			if (i + p > s.length) return null;
			if (s.substr(i, p) != prefix) return null;
			final j = i + p;
			// Require whitespace after the flag to avoid matching `--macroFoo`.
			if (j < s.length && !isSpace(s.charCodeAt(j))) return null;
			var k = j;
			while (k < s.length && isSpace(s.charCodeAt(k))) k++;
			final rest = StringTools.rtrim(s.substr(k));
			if (rest.length == 0) {
				Sys.println("hxhx(stage1): missing value after " + prefix);
				return null;
			}
			return [prefix, rest];
		}

		final macroLine = restOfLineAfter("--macro");
		if (macroLine != null) return macroLine;
		final cmdLine = restOfLineAfter("--cmd");
		if (cmdLine != null) return cmdLine;

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

			// Treat quotes as quoting delimiters only when they begin a token.
			// Upstream `.hxml` files can contain literal quote characters inside tokens
			// (e.g. in `--resource` names), and we must not interpret those as opening quotes.
			if (quote == 0 && cur.length == 0 && (c == "\"".code || c == "'".code)) {
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
