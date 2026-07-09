package haxe.format;

/**
	OCaml target override for `haxe.format.JsonParser`.

	Why
	- The default parser path relies on target EOF behavior that currently diverges in
	  the OCaml lane for some inputs.
	- We provide a deterministic parser implementation for portable JSON semantics.

	What
	- Parses JSON objects, arrays, strings, numbers, booleans, and null.
	- Returns anonymous structures for objects and `Array<Dynamic>` for arrays.

	How
	- Single-pass recursive descent parser with explicit index/EOF checks.
**/
class JsonParser {
	public static function parse(str:String):Dynamic {
		return new JsonParser(str).parseDocument();
	}

	final input:String;
	final length:Int;
	var index:Int;

	function new(input:String) {
		this.input = input;
		this.length = input.length;
		this.index = 0;
	}

	function parseDocument():Dynamic {
		skipWhitespace();
		final value = parseValue();
		skipWhitespace();
		if (!isEof()) {
			fail("Unexpected trailing token");
		}
		return value;
	}

	function parseValue():Dynamic {
		if (isEof()) {
			fail("Unexpected EOF");
		}
		final code = peekCode();
		return switch (code) {
			case "{".code: parseObject();
			case "[".code: parseArray();
			case "\"".code: parseString();
			case "t".code:
				expectKeyword("true");
				true;
			case "f".code:
				expectKeyword("false");
				false;
			case "n".code:
				expectKeyword("null");
				null;
			case "-".code, "0".code, "1".code, "2".code, "3".code, "4".code, "5".code, "6".code, "7".code, "8".code, "9".code:
				parseNumber();
			case _:
				fail("Invalid token");
				null;
		}
	}

	function parseObject():Dynamic {
		expectCode("{".code);
		skipWhitespace();
		final obj = {};
		if (consumeIf("}".code)) {
			return obj;
		}

		while (true) {
			skipWhitespace();
			final key = parseString();
			skipWhitespace();
			expectCode(":".code);
			skipWhitespace();
			final value = parseValue();
			Reflect.setField(obj, key, value);
			skipWhitespace();
			if (consumeIf("}".code)) {
				return obj;
			}
			expectCode(",".code);
		}
	}

	function parseArray():Array<Dynamic> {
		expectCode("[".code);
		skipWhitespace();
		final values:Array<Dynamic> = [];
		if (consumeIf("]".code)) {
			return values;
		}

		while (true) {
			skipWhitespace();
			values.push(parseValue());
			skipWhitespace();
			if (consumeIf("]".code)) {
				return values;
			}
			expectCode(",".code);
		}
	}

	function parseString():String {
		expectCode("\"".code);
		final buffer = new StringBuf();
		while (true) {
			if (isEof()) {
				fail("Unclosed string literal");
			}
			final code = nextCode();
			if (code == "\"".code) {
				return buffer.toString();
			}
			if (code == "\\".code) {
				if (isEof()) {
					fail("Invalid escape sequence");
				}
				final escaped = nextCode();
				switch (escaped) {
					case "\"".code, "\\".code, "/".code:
						buffer.addChar(escaped);
					case "b".code:
						buffer.addChar(8);
					case "f".code:
						buffer.addChar(12);
					case "n".code:
						buffer.addChar("\n".code);
					case "r".code:
						buffer.addChar("\r".code);
					case "t".code:
						buffer.addChar("\t".code);
					case "u".code:
						buffer.addChar(parseUnicodeEscape());
					case _:
						fail("Invalid escape sequence");
				}
			} else {
				buffer.addChar(code);
			}
		}
		return "";
	}

	function parseUnicodeEscape():Int {
		var value = 0;
		for (_ in 0...4) {
			if (isEof()) {
				fail("Invalid unicode escape");
			}
			final code = nextCode();
			final digit = switch (code) {
				case value if (value >= "0".code && value <= "9".code): value - "0".code;
				case value if (value >= "a".code && value <= "f".code): value - "a".code + 10;
				case value if (value >= "A".code && value <= "F".code): value - "A".code + 10;
				case _:
					fail("Invalid unicode escape");
					0;
			}
			value = (value << 4) | digit;
		}
		return value;
	}

	function parseNumber():Dynamic {
		final start = index;
		if (consumeIf("-".code)) {}
		parseDigits(false);
		var isFloat = false;
		if (consumeIf(".".code)) {
			isFloat = true;
			parseDigits(true);
		}
		final exponentCode = isEof() ? -1 : peekCode();
		if (exponentCode == "e".code || exponentCode == "E".code) {
			isFloat = true;
			nextCode();
			final signCode = isEof() ? -1 : peekCode();
			if (signCode == "+".code || signCode == "-".code) {
				nextCode();
			}
			parseDigits(true);
		}

		final token = input.substr(start, index - start);
		if (isFloat) {
			final floatValue = Std.parseFloat(token);
			if (Math.isNaN(floatValue)) {
				fail("Invalid float literal");
			}
			return floatValue;
		}
		final intValue = Std.parseInt(token);
		if (intValue == null) {
			fail("Invalid int literal");
		}
		return intValue;
	}

	function parseDigits(requireAtLeastOne:Bool):Void {
		var count = 0;
		while (!isEof()) {
			final code = peekCode();
			if (code < "0".code || code > "9".code) {
				break;
			}
			nextCode();
			count += 1;
		}
		if (requireAtLeastOne && count == 0) {
			fail("Expected digit");
		}
	}

	function expectKeyword(keyword:String):Void {
		for (i in 0...keyword.length) {
			if (isEof() || nextCode() != StringTools.fastCodeAt(keyword, i)) {
				fail("Invalid keyword");
			}
		}
	}

	function skipWhitespace():Void {
		while (!isEof()) {
			final code = peekCode();
			switch (code) {
				case " ".code, "\n".code, "\r".code, "\t".code:
					index += 1;
				case _:
					return;
			}
		}
	}

	inline function isEof():Bool {
		return index >= length;
	}

	inline function peekCode():Int {
		return StringTools.fastCodeAt(input, index);
	}

	inline function nextCode():Int {
		final code = StringTools.fastCodeAt(input, index);
		index += 1;
		return code;
	}

	function consumeIf(expected:Int):Bool {
		if (isEof()) {
			return false;
		}
		if (peekCode() != expected) {
			return false;
		}
		index += 1;
		return true;
	}

	function expectCode(expected:Int):Void {
		if (isEof() || nextCode() != expected) {
			fail("Unexpected token");
		}
	}

	function fail(message:String):Void {
		throw message + " at position " + index;
	}
}
