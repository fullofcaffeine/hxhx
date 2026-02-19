class Lexer {
	var s:String;
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

	function skipSpaces():Void {
		if (i < s.length) {
			final c:Int = cast s.charCodeAt(i);
			if (isSpace(c)) {
				i = i + 1;
				skipSpaces();
			}
		}
	}

	function readDigits(n:Int):Int {
		return if (i >= s.length) {
			n;
		} else {
			final d:Int = cast s.charCodeAt(i);
			if (isDigit(d)) {
				i = i + 1;
				readDigits(n * 10 + (d - 48));
			} else {
				n;
			}
		}
	}

	public function next():Token {
		skipSpaces();
		return if (i >= s.length) {
			TEof;
		} else {
			final c:Int = cast s.charCodeAt(i);
			i = i + 1;
			if (isDigit(c)) {
				final n = readDigits(c - 48);
				TInt(n);
			} else {
				switch (c) {
					case 43: TPlus; // +
					case 45: TMinus; // -
					case 42: TStar; // *
					case 47: TSlash; // /
					case 40: TLParen; // (
					case 41: TRParen; // )
					case _:
						throw "Unexpected character: " + String.fromCharCode(c);
				}
			}
		}
	}
}
