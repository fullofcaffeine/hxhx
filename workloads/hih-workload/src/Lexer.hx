class Lexer {
	final s:String;
	var i:Int;

	public function new(s:String) {
		this.s = s;
		this.i = 0;
	}

	static inline function isSpace(c:Int):Bool {
		return c == 32 || c == 9 || c == 10 || c == 13;
	}

	static inline function isDigit(c:Int):Bool {
		return c >= 48 && c <= 57;
	}

	static inline function isAlpha(c:Int):Bool {
		return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
	}

	function skipSpaces():Void {
		while (i < s.length && isSpace(s.charCodeAt(i))) {
			i = i + 1;
		}
	}

	function readWhile(pred:Int->Bool):String {
		final start = i;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (!pred(c))
				break;
			i = i + 1;
		}
		return s.substring(start, i);
	}

	function readInt(firstDigit:Int):Int {
		var n = firstDigit - 48;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (!isDigit(c))
				break;
			i = i + 1;
			n = n * 10 + (c - 48);
		}
		return n;
	}

	public function next():Token {
		skipSpaces();
		var out:Token = TEof;
		if (i < s.length) {
			final c = s.charCodeAt(i);
			i = i + 1;

			if (isDigit(c))
				out = TInt(readInt(c));
			else if (isAlpha(c)) {
				final rest = readWhile(ch -> isAlpha(ch) || isDigit(ch));
				out = TId(String.fromCharCode(c) + rest);
			} else {
				out = switch (c) {
					case 43: TPlus;
					case 45: TMinus;
					case 42: TStar;
					case 47: TSlash;
					case 61: TEquals;
					case 59: TSemi;
					case 40: TLParen;
					case 41: TRParen;
					case _:
						throw "Unexpected character: " + String.fromCharCode(c);
				}
			}
		}

		return out;
	}
}
