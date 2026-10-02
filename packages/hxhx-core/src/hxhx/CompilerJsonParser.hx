package hxhx;

/**
	Deterministic JSON parser for compiler-owned metadata documents.

	Plugin manifests and native macro-module receipts both need consistent decoding across
	interpreter, bootstrap, and native OCaml builds. Each parsed value has one of the
	closed `CompilerJsonValue` variants, including values nested in arrays or objects.
	This keeps native payload representations concrete without reflective field access.

	The parser throws the first syntax error with its source position. Callers remain
	responsible for matching the value variants against their own document schema.
**/
class CompilerJsonParser {
	public static function parse(content:String):CompilerJsonValue {
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

	function parseDocument():CompilerJsonValue {
		skipWhitespace();
		final value = parseValue();
		skipWhitespace();
		if (!isEof())
			fail("unexpected trailing token");
		return value;
	}

	function parseValue():CompilerJsonValue {
		if (isEof())
			fail("unexpected EOF");
		final code = peekCode();
		if (code == "{".code) {
			return parseObject();
		} else if (code == "[".code) {
			return parseArray();
		} else if (code == "\"".code) {
			return JsonString(parseString());
		} else if (code == "t".code) {
			expectKeyword("true");
			return JsonBool(true);
		} else if (code == "f".code) {
			expectKeyword("false");
			return JsonBool(false);
		} else if (code == "n".code) {
			expectKeyword("null");
			return JsonNull;
		} else if (code == "-".code || (code >= "0".code && code <= "9".code)) {
			return parseNumber();
		} else {
			throw "invalid token at position " + index;
		}
	}

	function parseObject():CompilerJsonValue {
		expectCode("{".code);
		skipWhitespace();
		final object = new haxe.ds.StringMap<CompilerJsonValue>();
		if (consumeIf("}".code))
			return JsonObject(object);

		while (true) {
			skipWhitespace();
			final key = parseString();
			skipWhitespace();
			expectCode(":".code);
			skipWhitespace();
			object.set(key, parseValue());
			skipWhitespace();
			if (consumeIf("}".code))
				return JsonObject(object);
			expectCode(",".code);
		}

		return JsonObject(object);
	}

	function parseArray():CompilerJsonValue {
		expectCode("[".code);
		skipWhitespace();
		final values:Array<CompilerJsonValue> = [];
		if (consumeIf("]".code))
			return JsonArray(values);

		while (true) {
			skipWhitespace();
			final value = parseValue();
			values.push(value);
			skipWhitespace();
			if (consumeIf("]".code))
				return JsonArray(values);
			expectCode(",".code);
		}

		return JsonArray(values);
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
		Retains the token's integer or floating-point kind in its JSON variant.
		Number scanning and conversion use the same rules as the other compiler routes.
	**/
	function parseNumber():CompilerJsonValue {
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
			return JsonFloat(parsedFloat);
		}
		final parsedInt = Std.parseInt(token);
		if (parsedInt == null)
			fail("invalid int literal");
		return JsonInt(parsedInt);
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
