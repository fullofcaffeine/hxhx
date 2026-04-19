/**
	Haxe-in-Haxe lexer (very small subset).

	Why:
	- This is the first concrete step toward a real Haxe compiler implemented in
	  Haxe: stop treating parsing as a stub and start producing a structured
	  representation of source code.
		- The goal is incremental: support just enough syntax to parse a single
		  Haxe module with 'package', 'import', and a class containing a
		  'static function main'.

	What:
		- Produces HxToken values from a source string.
		- Skips whitespace and Haxe comments (line comments '//' and block comments).
	- Recognizes a small set of keywords + punctuation + identifiers + strings.

	How:
		- The lexer maintains a cursor (index, line, column) and exposes next()
		  to advance one token at a time.
		- Strings are parsed as '\"'-delimited. Escape handling is minimal (enough for
		  simple acceptance fixtures) and will be expanded later.
**/
class HxLexer {
	final src:String;
	var index:Int = 0;
	var line:Int = 1;
	var column:Int = 1;

	public function new(src:String) {
		this.src = src;
	}

	inline function eof():Bool {
		return index >= src.length;
	}

	inline function peek(offset:Int = 0):Int {
		final i = index + offset;
		return i >= src.length ? -1 : (cast src.charCodeAt(i) : Int);
	}

	inline function bump():Int {
		final c = peek(0);
		index++;
		if (c == 10) { // \n
			line++;
			column = 1;
		} else if (c != 13) { // ignore \r for column accounting
			column++;
		}
		return c;
	}

	inline function pos():HxPos {
		return new HxPos(index, line, column);
	}

	static inline function isSpace(c:Int):Bool {
		return c == 9 || c == 10 || c == 13 || c == 32;
	}

	static inline function isIdentStart(c:Int):Bool {
		return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95; // A-Z a-z _
	}

	static inline function isIdentCont(c:Int):Bool {
		return isIdentStart(c) || (c >= 48 && c <= 57); // plus 0-9
	}

	static inline function isDigit(c:Int):Bool {
		return c >= 48 && c <= 57;
	}

	static inline function isHexDigit(c:Int):Bool {
		return isDigit(c) || (c >= "a".code && c <= "f".code) || (c >= "A".code && c <= "F".code);
	}

	static inline function isNumericSeparator(c:Int):Bool {
		return c == "_".code;
	}

	static inline function isNumericSuffixStart(c:Int):Bool {
		return c == "i".code || c == "I".code || c == "u".code || c == "U".code || c == "f".code || c == "F".code;
	}

	static function normalizeNumberText(text:String):String {
		return StringTools.replace(text == null ? "" : text, "_", "");
	}

	inline function isLeadingDotNumberStart():Bool {
		return isDigit(peek(1)) && (index == 0 || src.charCodeAt(index - 1) != ".".code);
	}

	function skipWhitespaceAndComments():Void {
		while (!eof()) {
			final c = peek(0);
			if (isSpace(c)) {
				bump();
				continue;
			}

			// Line comment: //
			if (c == 47 && peek(1) == 47) {
				bump();
				bump();
				while (!eof() && peek(0) != 10)
					bump();
				continue;
			}

			// Block comment: /* ... */
			if (c == 47 && peek(1) == 42) {
				bump();
				bump();
				while (!eof()) {
					final d = bump();
					if (d == 42 && peek(0) == 47) { // */
						bump();
						break;
					}
				}
				continue;
			}

			break;
		}
	}

	function readIdent(startPos:HxPos):HxToken {
		final start = index;
		bump(); // first char
		while (!eof() && isIdentCont(peek(0)))
			bump();
		final text = src.substring(start, index);
		return switch (text) {
			case "package": new HxToken(TKeyword(KPackage), startPos);
			case "import": new HxToken(TKeyword(KImport), startPos);
			case "using": new HxToken(TKeyword(KUsing), startPos);
			case "as": new HxToken(TKeyword(KAs), startPos);
			case "class": new HxToken(TKeyword(KClass), startPos);
			case "public": new HxToken(TKeyword(KPublic), startPos);
			case "private": new HxToken(TKeyword(KPrivate), startPos);
			case "static": new HxToken(TKeyword(KStatic), startPos);
			case "inline": new HxToken(TKeyword(KInline), startPos);
			case "function": new HxToken(TKeyword(KFunction), startPos);
			case "return": new HxToken(TKeyword(KReturn), startPos);
			case "if": new HxToken(TKeyword(KIf), startPos);
			case "else": new HxToken(TKeyword(KElse), startPos);
			case "switch": new HxToken(TKeyword(KSwitch), startPos);
			case "case": new HxToken(TKeyword(KCase), startPos);
			case "default": new HxToken(TKeyword(KDefault), startPos);
			case "try": new HxToken(TKeyword(KTry), startPos);
			case "catch": new HxToken(TKeyword(KCatch), startPos);
			case "throw": new HxToken(TKeyword(KThrow), startPos);
			case "while": new HxToken(TKeyword(KWhile), startPos);
			case "do": new HxToken(TKeyword(KDo), startPos);
			case "for": new HxToken(TKeyword(KFor), startPos);
			case "in": new HxToken(TKeyword(KIn), startPos);
			case "break": new HxToken(TKeyword(KBreak), startPos);
			case "continue": new HxToken(TKeyword(KContinue), startPos);
			case "untyped": new HxToken(TKeyword(KUntyped), startPos);
			case "cast": new HxToken(TKeyword(KCast), startPos);
			case "var": new HxToken(TKeyword(KVar), startPos);
			case "final": new HxToken(TKeyword(KFinal), startPos);
			case "new": new HxToken(TKeyword(KNew), startPos);
			case "this": new HxToken(TKeyword(KThis), startPos);
			case "super": new HxToken(TKeyword(KSuper), startPos);
			case "true": new HxToken(TKeyword(KTrue), startPos);
			case "false": new HxToken(TKeyword(KFalse), startPos);
			case "null": new HxToken(TKeyword(KNull), startPos);
			case _: new HxToken(TIdent(text), startPos);
		}
	}

	function readNumber(startPos:HxPos):HxToken {
		final start = index;
		while (!eof() && (isDigit(peek(0)) || isNumericSeparator(peek(0))))
			bump();

		// Hex integer literals (Stage 3 expansion): `0xFF`, `0X7fffff`.
		//
		// Why
		// - The Haxe stdlib uses hex constants heavily (bit masks, float helpers).
		// - Without hex support we tokenize `0xFF` as `0` + `x` + `FF`, which quickly
		//   cascades into parse drift inside expressions.
		if (!eof() && index == start + 1 && src.charCodeAt(start) == "0".code && (peek(0) == "x".code || peek(0) == "X".code)) {
			bump(); // 'x' or 'X'
			while (!eof()) {
				final c = peek(0);
				if (!isHexDigit(c) && !isNumericSeparator(c))
					break;
				bump();
			}
			final numericEnd = index;
			consumeNumericSuffix();
			final text = normalizeNumberText(src.substring(start, numericEnd));
			final value = Std.parseInt(text);
			return new HxToken(TInt(value == null ? 0 : value), startPos);
		}

		var isFloat = false;
		if (!eof() && peek(0) == ".".code && peek(1) != ".".code && (isDigit(peek(1)) || !isIdentStart(peek(1)))) {
			isFloat = true;
			bump(); // '.'
			while (!eof() && (isDigit(peek(0)) || isNumericSeparator(peek(0))))
				bump();
		}

		// Scientific notation (Stage 3 expansion): `1e-5`, `1E10`, `3.14e+2`.
		//
		// Why
		// - Upstream-ish test suites (e.g. utest) use constants like `1e-5`.
		// - Without exponent support, we tokenize `1e-5` as `TInt(1)` then `TIdent("e")`..., which
		//   cascades into `EUnsupported` placeholders in bring-up rungs.
		if (!eof() && (peek(0) == "e".code || peek(0) == "E".code)) {
			var off = 1;
			final sign = peek(1);
			if (sign == "+".code || sign == "-".code)
				off = 2;
			if (isDigit(peek(off))) {
				isFloat = true;
				bump(); // 'e' or 'E'
				if (peek(0) == "+".code || peek(0) == "-".code)
					bump();
				while (!eof() && (isDigit(peek(0)) || isNumericSeparator(peek(0))))
					bump();
			}
		}

		final numericEnd = index;
		final suffix = consumeNumericSuffix();
		final text = normalizeNumberText(src.substring(start, numericEnd));
		if (isFloat || StringTools.startsWith(suffix.toLowerCase(), "f")) {
			final value = Std.parseFloat(text);
			return new HxToken(TFloat(value), startPos);
		}
		final value = Std.parseInt(text);
		return new HxToken(TInt(value == null ? 0 : value), startPos);
	}

	function readLeadingDotNumber(startPos:HxPos):HxToken {
		final start = index;
		bump(); // '.'
		while (!eof() && (isDigit(peek(0)) || isNumericSeparator(peek(0))))
			bump();

		if (!eof() && (peek(0) == "e".code || peek(0) == "E".code)) {
			var off = 1;
			final sign = peek(1);
			if (sign == "+".code || sign == "-".code)
				off = 2;
			if (isDigit(peek(off))) {
				bump(); // 'e' or 'E'
				if (peek(0) == "+".code || peek(0) == "-".code)
					bump();
				while (!eof() && (isDigit(peek(0)) || isNumericSeparator(peek(0))))
					bump();
			}
		}

		final numericEnd = index;
		consumeNumericSuffix();
		final text = normalizeNumberText(src.substring(start, numericEnd));
		return new HxToken(TFloat(Std.parseFloat(text)), startPos);
	}

	function consumeNumericSuffix():String {
		final start = index;
		if (!eof() && isNumericSuffixStart(peek(0))) {
			bump();
			while (!eof() && isIdentCont(peek(0)))
				bump();
		}
		return src.substring(start, index);
	}

	function copyQuotedInterpolationPart(buf:StringBuf, quote:Int):Void {
		// The opening quote has already been copied. Copy until the matching close,
		// preserving escaped characters so braces inside nested strings do not affect
		// the surrounding `${...}` depth.
		while (!eof()) {
			final c = bump();
			buf.addChar(c);
			if (c == "\\".code) {
				if (!eof())
					buf.addChar(bump());
				continue;
			}
			if (c == quote)
				return;
		}
	}

	function copyInterpolationBracePayload(buf:StringBuf):Void {
		// Called after `${` has been copied from inside an outer string.
		//
		// Why
		// - Interpolation payloads are expressions, so quotes inside them belong to
		//   the payload, not to the enclosing string literal.
		// - Without this, a string like `'value ${Config.read('key')}'` terminates at
		//   the inner `'key'` and leaves the body parser at a `body_parse_error`.
		var depth = 1;
		while (!eof() && depth > 0) {
			final c = bump();
			buf.addChar(c);
			switch (c) {
				case "'".code | "\"".code:
					copyQuotedInterpolationPart(buf, c);
				case "{".code:
					depth++;
				case "}".code:
					depth--;
				case "\\".code:
					if (!eof())
						buf.addChar(bump());
				case _:
			}
		}
	}

	function readString(startPos:HxPos):HxToken {
		// Opening quote
		bump();
		final buf = new StringBuf();

		function hexVal(c:Int):Int {
			return if (c >= "0".code && c <= "9".code) {
				c - "0".code;
			} else if (c >= "a".code && c <= "f".code) {
				10 + (c - "a".code);
			} else if (c >= "A".code && c <= "F".code) {
				10 + (c - "A".code);
			} else {
				-1;
			};
		}

		function readHexDigits(count:Int):Int {
			var acc = 0;
			for (_ in 0...count) {
				final c = peek(0);
				if (c == -1)
					return -1;
				final v = hexVal(c);
				if (v < 0)
					return -1;
				acc = (acc << 4) | v;
				bump();
			}
			return acc;
		}

		while (!eof()) {
			final c = bump();
			if (c == "$".code && peek(0) == "{".code) {
				buf.addChar(c);
				buf.addChar(bump());
				copyInterpolationBracePayload(buf);
				continue;
			}
			if (c == 34) { // "
				return new HxToken(TString(buf.toString(), false), startPos);
			}
			if (c == 92) { // backslash
				if (eof())
					break;
				final esc = bump();
				switch (esc) {
					case 34:
						buf.addChar(34);
					case 92:
						buf.addChar(92);
					case 110:
						buf.addChar(10); // \n
					case 114:
						buf.addChar(13); // \r
					case 116:
						buf.addChar(9); // \t
					case "x".code:
						// Hex byte escape: \xNN
						final v = readHexDigits(2);
						if (v < 0) {
							buf.addChar("x".code);
						} else {
							buf.addChar(v);
						}
					case "u".code:
						// Unicode escape: \uNNNN
						final v = readHexDigits(4);
						if (v < 0) {
							buf.addChar("u".code);
						} else {
							buf.addChar(v);
						}
					case _:
						buf.addChar(esc); // best-effort
				}
				continue;
			}
			buf.addChar(c);
		}
		throw new HxParseError("Unterminated string literal", startPos);
	}

	function readSingleQuotedString(startPos:HxPos):HxToken {
		// Opening quote
		bump();
		final buf = new StringBuf();

		function hexVal(c:Int):Int {
			return if (c >= "0".code && c <= "9".code) {
				c - "0".code;
			} else if (c >= "a".code && c <= "f".code) {
				10 + (c - "a".code);
			} else if (c >= "A".code && c <= "F".code) {
				10 + (c - "A".code);
			} else {
				-1;
			};
		}

		function readHexDigits(count:Int):Int {
			var acc = 0;
			for (_ in 0...count) {
				final c = peek(0);
				if (c == -1)
					return -1;
				final v = hexVal(c);
				if (v < 0)
					return -1;
				acc = (acc << 4) | v;
				bump();
			}
			return acc;
		}

		while (!eof()) {
			final c = bump();
			if (c == "$".code && peek(0) == "{".code) {
				buf.addChar(c);
				buf.addChar(bump());
				copyInterpolationBracePayload(buf);
				continue;
			}
			if (c == "'".code) {
				return new HxToken(TString(buf.toString(), true), startPos);
			}
			if (c == 92) { // backslash
				if (eof())
					break;
				final esc = bump();
				switch (esc) {
					case "'".code:
						buf.addChar("'".code);
					case 92:
						buf.addChar(92);
					case 110:
						buf.addChar(10); // \n
					case 114:
						buf.addChar(13); // \r
					case 116:
						buf.addChar(9); // \t
					case "x".code:
						final v = readHexDigits(2);
						if (v < 0) {
							buf.addChar("x".code);
						} else {
							buf.addChar(v);
						}
					case "u".code:
						final v = readHexDigits(4);
						if (v < 0) {
							buf.addChar("u".code);
						} else {
							buf.addChar(v);
						}
					case _:
						buf.addChar(esc); // best-effort
				}
				continue;
			}
			buf.addChar(c);
		}
		throw new HxParseError("Unterminated string literal", startPos);
	}

	function readRegexLiteral(startPos:HxPos):HxToken {
		// Regex literal: `~/pattern/flags`.
		//
		// Why this lives in the lexer
		// - Regex bodies can contain `//` and escaped slashes. If the parser tries to
		//   consume those characters through normal tokenization, the lexer can classify
		//   part of the regex as a line comment.
		// - Returning a single token preserves the exact pattern text and keeps postfix
		//   parsing (`~/x/.match(...)`) in the normal expression parser.
		bump(); // '~'
		bump(); // '/'
		final pattern = new StringBuf();
		var escaped = false;
		while (!eof()) {
			final c = bump();
			if (escaped) {
				pattern.addChar(c);
				escaped = false;
				continue;
			}
			if (c == "\\".code) {
				pattern.addChar(c);
				escaped = true;
				continue;
			}
			if (c == "/".code) {
				final flags = new StringBuf();
				while (!eof()) {
					final f = peek(0);
					final isLower = f >= "a".code && f <= "z".code;
					final isUpper = f >= "A".code && f <= "Z".code;
					if (!isLower && !isUpper)
						break;
					flags.addChar(bump());
				}
				return new HxToken(TRegex(pattern.toString(), flags.toString()), startPos);
			}
			pattern.addChar(c);
		}
		throw new HxParseError("Unterminated regex literal", startPos);
	}

	public function next():HxToken {
		skipWhitespaceAndComments();
		final p = pos();
		if (eof())
			return new HxToken(TEof, p);

		final c = peek(0);
		return switch (c) {
			case 123:
				bump();
				new HxToken(TLBrace, p); // {
			case 125:
				bump();
				new HxToken(TRBrace, p); // }
			case 40:
				bump();
				new HxToken(TLParen, p); // (
			case 41:
				bump();
				new HxToken(TRParen, p); // )
			case 59:
				bump();
				new HxToken(TSemicolon, p); // ;
			case 58:
				bump();
				new HxToken(TColon, p); // :
			case 46 if (isLeadingDotNumberStart()):
				readLeadingDotNumber(p);
			case 46:
				bump();
				new HxToken(TDot, p); // .
			case 44:
				bump();
				new HxToken(TComma, p); // ,
			case 34: readString(p); // "
			case 39: readSingleQuotedString(p); // '
			case _ if (isDigit(c)): readNumber(p);
			case _ if (isIdentStart(c)): readIdent(p);
			case 126 if (peek(1) == 47): readRegexLiteral(p); // ~/
			case _:
				// Bootstrap behavior: do not fail on unknown punctuation yet.
				// We only need enough tokenization to skip bodies and find top-level
				// declarations; full expression/type lexing comes later.
				bump();
				new HxToken(TOther(c), p);
		}
	}
}
