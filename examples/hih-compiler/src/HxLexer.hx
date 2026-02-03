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

	function skipWhitespaceAndComments():Void {
		while (!eof()) {
			final c = peek(0);
			if (isSpace(c)) {
				bump();
				continue;
			}

			// Line comment: //
			if (c == 47 && peek(1) == 47) {
				bump(); bump();
				while (!eof() && peek(0) != 10) bump();
				continue;
			}

			// Block comment: /* ... */
			if (c == 47 && peek(1) == 42) {
				bump(); bump();
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
		while (!eof() && isIdentCont(peek(0))) bump();
		final text = src.substring(start, index);
		return switch (text) {
			case "package": new HxToken(TKeyword(KPackage), startPos);
			case "import": new HxToken(TKeyword(KImport), startPos);
			case "class": new HxToken(TKeyword(KClass), startPos);
			case "static": new HxToken(TKeyword(KStatic), startPos);
			case "function": new HxToken(TKeyword(KFunction), startPos);
			case _: new HxToken(TIdent(text), startPos);
		}
	}

	function readString(startPos:HxPos):HxToken {
		// Opening quote
		bump();
		final buf = new StringBuf();
		while (!eof()) {
			final c = bump();
			if (c == 34) { // "
				return new HxToken(TString(buf.toString()), startPos);
			}
			if (c == 92) { // backslash
				if (eof()) break;
				final esc = bump();
				switch (esc) {
					case 34: buf.addChar(34);
					case 92: buf.addChar(92);
					case 110: buf.addChar(10); // \n
					case 114: buf.addChar(13); // \r
					case 116: buf.addChar(9);  // \t
					case _: buf.addChar(esc); // best-effort
				}
				continue;
			}
			buf.addChar(c);
		}
		throw new HxParseError("Unterminated string literal", startPos);
	}

	public function next():HxToken {
		skipWhitespaceAndComments();
		final p = pos();
		if (eof()) return new HxToken(TEof, p);

		final c = peek(0);
		return switch (c) {
			case 123: bump(); new HxToken(TLBrace, p);      // {
			case 125: bump(); new HxToken(TRBrace, p);      // }
			case 40:  bump(); new HxToken(TLParen, p);      // (
			case 41:  bump(); new HxToken(TRParen, p);      // )
			case 59:  bump(); new HxToken(TSemicolon, p);   // ;
			case 58:  bump(); new HxToken(TColon, p);       // :
			case 46:  bump(); new HxToken(TDot, p);         // .
			case 44:  bump(); new HxToken(TComma, p);       // ,
			case 34:  readString(p);                        // "
			case _ if (isIdentStart(c)): readIdent(p);
			case _:
				// Bootstrap behavior: do not fail on unknown punctuation yet.
				// We only need enough tokenization to skip bodies and find top-level
				// declarations; full expression/type lexing comes later.
				bump();
				new HxToken(TOther(c), p);
		}
	}
}
