/**
	Conditional compilation filter for bootstrap parsing (`#if`, `#elseif`, `#else`, `#end`).

	Why
	- Upstream-ish Haxe code uses conditional compilation per-target and per-mode:
	  - `#if java` / `#if cs` / `#if js` branches reference target-specific externs and helpers.
	  - `#if macro` sections are only meaningful during macro typing/execution.
	  - `#if (dce == "full") && !interp` appears in upstream unit code.
	- During Stage 1/3 bring-up, we do not implement a full preprocessor, but we *must*
	  avoid treating inactive branches as active source:
	  - it can cause false `import_missing` failures,
	  - it can pull huge dependency surfaces that are irrelevant for the current target,
	  - it makes the module graph non-deterministic.

	What
	- `filterSource(source, defines)` returns a string with the same length and line breaks
	  as the input, where:
	  - inactive `#if` branches are replaced by spaces (newlines preserved),
	  - directive lines themselves are replaced by spaces (newlines preserved).
	- The output is safe to feed into our bootstrap lexers/parsers (native or pure Haxe),
	  because it contains no literal `#if` tokens.

	How
	- Scan line-by-line and recognize directives only at the beginning of a physical line
	  (after optional whitespace).
	- Evaluate a small boolean expression subset:
	  - identifiers, `!`, `&&`, `||`, parentheses
	  - `ident == "string"` and `ident != "string"` comparisons
	- Unknown identifiers are treated as false (conservative).

	Gotchas
	- This is not a full Haxe preprocessor: it intentionally ignores directives that appear
	  mid-line or inside strings/comments.
	- It is meant to unblock Gate bring-up; grow it only when a gate/test requires it.
**/
class HxConditionalCompilation {
	private static inline function isSpace(c:Int):Bool {
		return c == 9 || c == 32; // \t or space
	}

	private static inline function isLineWs(c:Int):Bool {
		return c == 9 || c == 10 || c == 13 || c == 32; // \t \n \r space
	}

	private static function makeBlankLineLike(line:String):String {
		if (line == null || line.length == 0) return line;
		final b = new StringBuf();
		for (i in 0...line.length) {
			final c = line.charCodeAt(i);
			b.addChar(c == "\n".code ? "\n".code : (c == "\r".code ? "\r".code : " ".code));
		}
		return b.toString();
	}

	/**
		Filter a whole source string.

		Why
		- Both the native frontend seam (`-D hih_native_parser`) and the pure-Haxe parser
		  accept raw source strings. Filtering at this boundary ensures both frontends see
		  the same active surface.
	**/
	public static function filterSource(source:String, defines:haxe.ds.StringMap<String>):String {
		if (source == null || source.length == 0) return source;

		final lines = splitLinesPreserveNewlines(source);
		final out = new StringBuf();

		// Each stack frame represents a single `#if ...` block.
		//
		// parentActive: whether this whole block is visible due to outer blocks.
		// branchActive: whether the *current* branch (#if/#elseif/#else) is active.
		// seenTrue: whether a previous branch in this block matched.
		final stack = new Array<{parentActive:Bool, branchActive:Bool, seenTrue:Bool}>();
		var currentActive = true;

		for (line in lines) {
			final directive = parseDirectiveLine(line);
			if (directive == null) {
				if (!currentActive) {
					out.add(makeBlankLineLike(line));
					continue;
				}

				// Bootstrap preprocessor extension: handle a small subset of inline conditionals.
				//
				// Why
				// - Upstream stdlib frequently uses inline `#if ... #else ... #end` in expressions, e.g.:
				//     var b = #if (js || hl) @:privateAccess s.b #else s.getData() #end;
				// - The stage1/stage3 frontends are not full preprocessors, so leaving `#` tokens in
				//   the active source causes parse failures / unsupported-expr diagnostics.
				//
				// What
				// - We rewrite the line to keep only the active branch (best-effort) while blanking
				//   the directive tokens and inactive branch with spaces (newlines preserved).
				//
				// Non-goals
				// - Full nested inline preprocessing.
				// - Correct handling inside strings/comments (best-effort heuristics only).
				final inlineFiltered = filterInlineConditionals(line, defines);
				out.add(inlineFiltered == null ? line : inlineFiltered);
				continue;
			}

			// Always blank directive lines so the parser doesn't see `#`.
			out.add(makeBlankLineLike(line));

			final outerActive = stack.length == 0 ? true : stack[stack.length - 1].parentActive && stack[stack.length - 1].branchActive;

			switch (directive.kind) {
				case "if":
					final cond = outerActive && evalExpr(directive.expr, defines);
					stack.push({parentActive: outerActive, branchActive: cond, seenTrue: cond});
				case "elseif":
					if (stack.length == 0) {
						// Malformed; ignore.
					} else {
						final top = stack[stack.length - 1];
						if (!top.parentActive) {
							top.branchActive = false;
						} else if (top.seenTrue) {
							top.branchActive = false;
						} else {
							final cond = evalExpr(directive.expr, defines);
							top.branchActive = cond;
							if (cond) top.seenTrue = true;
						}
						stack[stack.length - 1] = top;
					}
				case "else":
					if (stack.length == 0) {
						// Malformed; ignore.
					} else {
						final top = stack[stack.length - 1];
						top.branchActive = top.parentActive && !top.seenTrue;
						top.seenTrue = true;
						stack[stack.length - 1] = top;
					}
				case "end":
					if (stack.length > 0) stack.pop();
				case _:
			}

			// Recompute currentActive from the full stack.
			currentActive = true;
			for (f in stack) {
				if (!f.parentActive || !f.branchActive) {
					currentActive = false;
					break;
				}
			}
		}

		return out.toString();
	}

	/**
		Filter a single physical line that contains an inline `#if ... #else ... #end`.

		Returns `null` if the line does not contain a supported inline construct.
	**/
	private static function filterInlineConditionals(line:String, defines:haxe.ds.StringMap<String>):Null<String> {
		if (line == null || line.length == 0) return null;
		// Fast-path: avoid scanning most lines.
		if (line.indexOf("#if") == -1) return null;

		// Only attempt when there's a matching `#end` somewhere later.
		if (line.indexOf("#end") == -1) return null;

		// Find a `#if` token outside string literals.
		final idxIf = findTokenOutsideStrings(line, "#if", 0);
		if (idxIf < 0) return null;

		final idxEnd = findTokenOutsideStrings(line, "#end", idxIf + 3);
		if (idxEnd < 0) return null;

		// Optional `#else`.
		final idxElse = findTokenOutsideStrings(line, "#else", idxIf + 3);
		final elseInRange = idxElse >= 0 && idxElse < idxEnd;
		final idxElse0 = elseInRange ? idxElse : -1;

		// Parse the condition boundary so we can separate it from the "then" expression.
		var condStart = idxIf + 3;
		while (condStart < line.length && isLineWs(line.charCodeAt(condStart))) condStart++;
		if (condStart >= line.length) return null;

		final condEnd = parseInlineCondEnd(line, condStart, idxEnd);
		if (condEnd <= condStart) return null;

		final condText = StringTools.trim(line.substr(condStart, condEnd - condStart));
		final thenStart = condEnd;
		final thenEnd = idxElse0 >= 0 ? idxElse0 : idxEnd;
		final elseStart = idxElse0 >= 0 ? (idxElse0 + 5) : -1; // "#else".length == 5
		final elseEnd = idxEnd;

		// Decide which branch is active.
		final takeThen = evalExpr(condText, defines);
		final keepStart = takeThen ? thenStart : elseStart;
		final keepEnd = takeThen ? thenEnd : elseEnd;
		if (keepStart < 0 || keepEnd < keepStart) {
			// No else branch and condition is false: keep nothing.
			return makeBlankLineLike(line);
		}

		// Build an output line of the same length that keeps:
		// - prefix before #if
		// - chosen branch payload
		// - suffix after #end
		final outCodes = new Array<Int>();
		outCodes.resize(line.length);
		for (i in 0...line.length) {
			final c = line.charCodeAt(i);
			outCodes[i] = (c == "\n".code || c == "\r".code) ? c : " ".code;
		}

		inline function copyRange(a:Int, b:Int):Void {
			var i = a;
			while (i < b && i < line.length) {
				outCodes[i] = line.charCodeAt(i);
				i++;
			}
		}

		copyRange(0, idxIf);
		copyRange(keepStart, keepEnd);
		copyRange(idxEnd + 4, line.length); // "#end".length == 4

		final b = new StringBuf();
		for (c in outCodes) b.addChar(c);
		return b.toString();
	}

	private static function parseInlineCondEnd(line:String, start:Int, max:Int):Int {
		// If the condition starts with `(`, scan to the matching `)`.
		// Otherwise, scan to the next whitespace.
		final first = line.charCodeAt(start);
		if (first == "(".code) {
			var depth = 0;
			var i = start;
			while (i < line.length && i < max) {
				final c = line.charCodeAt(i);
				if (c == "(".code) {
					depth++;
				} else if (c == ")".code) {
					depth--;
					if (depth == 0) return i + 1;
				} else if (c == "\"".code || c == "'".code) {
					// Skip over quoted strings inside the condition (best-effort).
					i = skipStringLiteral(line, i, c, max);
					continue;
				}
				i++;
			}
			return -1;
		}

		var i = start;
		while (i < line.length && i < max && !isLineWs(line.charCodeAt(i))) i++;
		return i;
	}

	private static function skipStringLiteral(line:String, start:Int, quote:Int, max:Int):Int {
		// start points at the opening quote
		var i = start + 1;
		while (i < line.length && i < max) {
			final c = line.charCodeAt(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == quote) return i + 1;
			i++;
		}
		return i;
	}

	private static function findTokenOutsideStrings(line:String, token:String, from:Int):Int {
		if (line == null || token == null) return -1;
		if (token.length == 0) return -1;

		var i = from < 0 ? 0 : from;
		var inQuote = 0; // 0 = none, otherwise quote charcode
		while (i <= line.length - token.length) {
			final c = line.charCodeAt(i);
			if (inQuote != 0) {
				if (c == "\\".code) {
					i += 2;
					continue;
				}
				if (c == inQuote) {
					inQuote = 0;
				}
				i++;
				continue;
			}

			if (c == "\"".code || c == "'".code) {
				inQuote = c;
				i++;
				continue;
			}

			// Very small comment heuristic: do not match inside `//` comment tails.
			if (c == "/".code && i + 1 < line.length && line.charCodeAt(i + 1) == "/".code) {
				return -1;
			}

			if (line.substr(i, token.length) == token) return i;
			i++;
		}
		return -1;
	}

	private static function splitLinesPreserveNewlines(s:String):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c == "\n".code) {
				out.push(s.substr(start, i - start + 1));
				i += 1;
				start = i;
				continue;
			}
			i += 1;
		}
		if (start < s.length) out.push(s.substr(start));
		return out;
	}

	private static function stripLineCommentOutsideStrings(s:String):String {
		if (s == null || s.length == 0) return s;
		var i = 0;
		var inSingle = false;
		var inDouble = false;
		var escaped = false;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (escaped) {
				escaped = false;
				i += 1;
				continue;
			}
			if (c == "\\".code && (inSingle || inDouble)) {
				escaped = true;
				i += 1;
				continue;
			}
			if (!inSingle && c == "\"".code) {
				inDouble = !inDouble;
				i += 1;
				continue;
			}
			if (!inDouble && c == "'".code) {
				inSingle = !inSingle;
				i += 1;
				continue;
			}
			if (!inSingle && !inDouble && c == "/".code && i + 1 < s.length && s.charCodeAt(i + 1) == "/".code) {
				return s.substr(0, i);
			}
			i += 1;
		}
		return s;
	}

	private static function parseDirectiveLine(line:String):Null<{kind:String, expr:String}> {
		if (line == null) return null;
		var i = 0;
		while (i < line.length && isSpace(line.charCodeAt(i))) i++;
		if (i >= line.length) return null;
		if (line.charCodeAt(i) != "#".code) return null;
		i++;
		while (i < line.length && isSpace(line.charCodeAt(i))) i++;

		final rest = line.substr(i);
		final restNoComment = stripLineCommentOutsideStrings(rest);
		// This bootstrap preprocessor only supports directives that occupy the whole
		// physical line. Haxe also allows “inline” conditional compilation like:
		//   #if (cond) expr #else other #end(...)
		// on a *single* physical line. If we treat that as a normal `#if` directive,
		// we would push to the stack but never observe `#end`, causing the remainder
		// of the file to be blanked (catastrophic for parsing).
		//
		// Heuristic: if there's any additional `#` after the initial one, treat the
		// line as an opaque preprocessor construct. We still blank it (so parsers
		// never see `#` tokens), but we do not mutate the conditional stack.
		//
		// Strip trailing `//` comment text first so cases like:
		//   #if cs // issue #996
		// do not get misclassified as opaque.
		if (restNoComment.indexOf("#") != -1) return {kind: "opaque", expr: ""};
		final trimmed = StringTools.trim(restNoComment);
		if (StringTools.startsWith(trimmed, "if ")) return {kind: "if", expr: StringTools.trim(trimmed.substr(3))};
		if (StringTools.startsWith(trimmed, "elseif ")) return {kind: "elseif", expr: StringTools.trim(trimmed.substr(7))};
		if (trimmed == "else") return {kind: "else", expr: ""};
		if (trimmed == "end") return {kind: "end", expr: ""};
		return null;
	}

	// --- Expression evaluator (small subset) ---

	private static function evalExpr(expr:String, defines:haxe.ds.StringMap<String>):Bool {
		final p = new ExprParser(expr == null ? "" : expr, defines);
		return p.parse();
	}
}

private enum Token {
	TIdent(name:String);
	TString(value:String);
	TNot;
	TAnd;
	TOr;
	TLParen;
	TRParen;
	TEq;
	TNeq;
	TEof;
}

private class ExprLexer {
	final s:String;
	var i:Int = 0;

	public function new(s:String) {
		this.s = s == null ? "" : s;
	}

	inline function eof():Bool return i >= s.length;
	inline function peek(off:Int = 0):Int {
		final j = i + off;
		return j >= s.length ? -1 : s.charCodeAt(j);
	}
	inline function bump():Int return eof() ? -1 : s.charCodeAt(i++);
	inline function isWs(c:Int):Bool return c == 9 || c == 10 || c == 13 || c == 32;
	inline function isIdentStart(c:Int):Bool return (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code) || c == "_".code;
	inline function isIdentCont(c:Int):Bool return isIdentStart(c) || (c >= "0".code && c <= "9".code);

	function skipWs():Void {
		while (!eof() && isWs(peek())) i++;
	}

	function readIdent():String {
		final start = i;
		bump();
		while (!eof() && isIdentCont(peek())) bump();
		return s.substr(start, i - start);
	}

	function readString(q:Int):String {
		// opening quote already in `q`
		bump();
		final b = new StringBuf();
		while (!eof()) {
			final c = bump();
			if (c == q) return b.toString();
			if (c == "\\".code && !eof()) {
				final esc = bump();
				switch (esc) {
					case "n".code: b.addChar("\n".code);
					case "r".code: b.addChar("\r".code);
					case "t".code: b.addChar("\t".code);
					case "\\".code: b.addChar("\\".code);
					case "\"".code: b.addChar("\"".code);
					case "'".code: b.addChar("'".code);
					case _: b.addChar(esc);
				}
				continue;
			}
			b.addChar(c);
		}
		return b.toString();
	}

	public function next():Token {
		skipWs();
		if (eof()) return TEof;
		return switch (peek()) {
			case "!".code:
				if (peek(1) == "=".code) {
					i += 2;
					TNeq;
				} else {
					i++;
					TNot;
				}
			case "&".code:
				if (peek(1) == "&".code) {
					i += 2;
					TAnd;
				} else {
					i++;
					TEof;
				}
			case "|".code:
				if (peek(1) == "|".code) {
					i += 2;
					TOr;
				} else {
					i++;
					TEof;
				}
			case "(".code:
				i++;
				TLParen;
			case ")".code:
				i++;
				TRParen;
			case "=".code:
				if (peek(1) == "=".code) {
					i += 2;
					TEq;
				} else {
					i++;
					TEof;
				}
			case "\"".code, "'".code:
				final q = peek();
				TString(readString(q));
			case c if (isIdentStart(c)):
				TIdent(readIdent());
			case _:
				i++;
				next();
		}
	}
}

private class ExprParser {
	final lex:ExprLexer;
	final defines:haxe.ds.StringMap<String>;
	var cur:Token;

	public function new(expr:String, defines:haxe.ds.StringMap<String>) {
		this.lex = new ExprLexer(expr);
		this.defines = defines == null ? new haxe.ds.StringMap<String>() : defines;
		this.cur = lex.next();
	}

	inline function bump():Void cur = lex.next();

	public function parse():Bool {
		final v = parseOr();
		return v;
	}

	function parseOr():Bool {
		var left = parseAnd();
		while (true) {
			switch (cur) {
				case TOr:
					bump();
					left = left || parseAnd();
				case _:
					return left;
			}
		}
	}

	function parseAnd():Bool {
		var left = parseUnary();
		while (true) {
			switch (cur) {
				case TAnd:
					bump();
					left = left && parseUnary();
				case _:
					return left;
			}
		}
	}

	function parseUnary():Bool {
		return switch (cur) {
			case TNot:
				bump();
				!parseUnary();
			case _:
				parsePrimary();
		}
	}

	function parsePrimary():Bool {
		return switch (cur) {
			case TLParen:
				bump();
				final v = parseOr();
				if (cur.match(TRParen)) bump();
				v;
			case TIdent(name):
				bump();
				parseIdentTail(name);
			case _:
				// Conservative default: any unrecognized expression part becomes false.
				bump();
				false;
		}
	}

	function parseIdentTail(name:String):Bool {
		// Support `defined(NAME)` as a cheap convenience.
		if (name == "defined" && cur.match(TLParen)) {
			bump();
			var key = "";
			switch (cur) {
				case TIdent(n):
					key = n;
					bump();
				case TString(s):
					key = s;
					bump();
				case _:
			}
			if (cur.match(TRParen)) bump();
			return key.length > 0 && defines.exists(key);
		}

		// Optional `== "..."` / `!= "..."`.
		return switch (cur) {
			case TEq:
				bump();
				final lit = parseStringLit();
				(definedValue(name) == lit);
			case TNeq:
				bump();
				final lit = parseStringLit();
				(definedValue(name) != lit);
			case _:
				defines.exists(name);
		}
	}

	function parseStringLit():String {
		return switch (cur) {
			case TString(s):
				bump();
				s;
			case TIdent(s):
				// Allow bare idents as “strings” to keep the subset permissive (e.g. `dce == full`).
				bump();
				s;
			case _:
				"";
		}
	}

	function definedValue(name:String):String {
		if (name == null || name.length == 0) return "";
		return defines.exists(name) ? defines.get(name) : "";
	}
}
