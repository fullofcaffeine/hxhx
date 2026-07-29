package hxhx;

/**
	Deterministic JSON parser for compiler-owned metadata documents.

	Plugin manifests and native macro-module receipts both need consistent decoding across
	interpreter, bootstrap, and native OCaml lanes. This boundary avoids `haxe.Json.parse`
	because mixed `Dynamic` values can generate invalid unboxed OCaml when expression
	preprocessors are disabled.

	The parser accepts standard JSON values, boxes heterogeneous values explicitly, and
	throws the first syntax error with its source position. Callers remain responsible for
	validating their own document schema and converting the returned `Dynamic` value into
	typed structures.
**/
class CompilerJsonParser {
	public static function parse(content:String):Dynamic {
		return new CompilerJsonParser(content).parseDocument();
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
		if (!isEof())
			fail("unexpected trailing token");
		return value.value;
	}

	function parseValue():CompilerJsonValueBox {
		if (isEof())
			fail("unexpected EOF");
		final code = peekCode();
		var value = new CompilerJsonValueBox(null);
		if (code == "{".code) {
			value = new CompilerJsonValueBox(parseObject());
		} else if (code == "[".code) {
			value = new CompilerJsonValueBox(parseArray());
		} else if (code == "\"".code) {
			value = new CompilerJsonValueBox(parseString());
		} else if (code == "t".code) {
			expectKeyword("true");
			value = new CompilerJsonValueBox(true);
		} else if (code == "f".code) {
			expectKeyword("false");
			value = new CompilerJsonValueBox(false);
		} else if (code == "n".code) {
			expectKeyword("null");
			value = new CompilerJsonValueBox(null);
		} else if (code == "-".code || (code >= "0".code && code <= "9".code)) {
			value = parseNumber();
		} else {
			fail("invalid token");
		}
		return value;
	}

	function parseObject():Dynamic {
		expectCode("{".code);
		skipWhitespace();
		final object:Dynamic = {};
		if (consumeIf("}".code))
			return object;

		while (true) {
			skipWhitespace();
			final key = parseString();
			skipWhitespace();
			expectCode(":".code);
			skipWhitespace();
			Reflect.setField(object, key, parseValue().value);
			skipWhitespace();
			if (consumeIf("}".code))
				return object;
			expectCode(",".code);
		}

		return object;
	}

	function parseArray():CompilerJsonArray {
		expectCode("[".code);
		skipWhitespace();
		final values:Array<Dynamic> = [];
		if (consumeIf("]".code))
			return new CompilerJsonArray(values);

		while (true) {
			skipWhitespace();
			final value:Dynamic = parseValue().value;
			values.push(value);
			skipWhitespace();
			if (consumeIf("]".code))
				return new CompilerJsonArray(values);
			expectCode(",".code);
		}

		return new CompilerJsonArray(values);
	}

	function parseString():String {
		expectCode("\"".code);
		final buffer = new StringBuf();
		while (true) {
			if (isEof())
				fail("unclosed string literal");
			final code = nextCode();
			if (code == "\"".code)
				return buffer.toString();
			if (code == "\\".code) {
				if (isEof())
					fail("invalid escape sequence");
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
						fail("invalid escape sequence");
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
			if (isEof())
				fail("invalid unicode escape");
			final code = nextCode();
			final digit = switch (code) {
				case c if (c >= "0".code && c <= "9".code): c - "0".code;
				case c if (c >= "a".code && c <= "f".code): c - "a".code + 10;
				case c if (c >= "A".code && c <= "F".code): c - "A".code + 10;
				case _:
					fail("invalid unicode escape");
					0;
			}
			value = (value << 4) | digit;
		}
		return value;
	}

	/**
		Parses one JSON number and returns it through the parser's heterogeneous-value box.

		The concrete payload remains an `Int` when the token has no fraction or exponent
		and a `Float` otherwise. Returning the box instead of `Dynamic` keeps that union
		inside the JSON value boundary rather than exporting an unsealed dynamic function
		result to native targets.
	**/
	function parseNumber():CompilerJsonValueBox {
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
			if (signCode == "+".code || signCode == "-".code)
				nextCode();
			parseDigits(true);
		}

		final token = input.substr(start, index - start);
		if (isFloat) {
			final parsedFloat = Std.parseFloat(token);
			if (Math.isNaN(parsedFloat))
				fail("invalid float literal");
			return new CompilerJsonValueBox(parsedFloat);
		}
		final parsedInt = Std.parseInt(token);
		if (parsedInt == null)
			fail("invalid int literal");
		return new CompilerJsonValueBox(parsedInt);
	}

	function parseDigits(requireAtLeastOne:Bool):Void {
		var count = 0;
		while (!isEof()) {
			final code = peekCode();
			if (code < "0".code || code > "9".code)
				break;
			nextCode();
			count++;
		}
		if (requireAtLeastOne && count == 0)
			fail("expected digit");
	}

	function expectKeyword(keyword:String):Void {
		for (i in 0...keyword.length)
			if (isEof() || nextCode() != StringTools.fastCodeAt(keyword, i))
				fail("invalid keyword");
	}

	function skipWhitespace():Void {
		while (!isEof()) {
			final code = peekCode();
			switch (code) {
				case " ".code, "\n".code, "\r".code, "\t".code:
					index++;
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
		index++;
		return code;
	}

	function consumeIf(expected:Int):Bool {
		if (isEof() || peekCode() != expected)
			return false;
		index++;
		return true;
	}

	function expectCode(expected:Int):Void {
		if (isEof() || nextCode() != expected)
			fail("unexpected token");
	}

	function fail(message:String):Void {
		throw message + " at position " + index;
	}
}

private class CompilerJsonValueBox {
	public final value:Dynamic;

	public function new(value:Dynamic) {
		this.value = value;
	}
}
