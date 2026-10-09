/** A decoded escape and the first unconsumed source index, in the lexer's host indexing. */
typedef HxDecodedStringEscape = {
	final value:String;
	final nextIndex:Int;
}

/**
	Decode source escapes once for both quote forms before string interpolation.
	Unicode escapes denote scalar values, not UTF-16 surrogate halves. Hexadecimal
	and octal byte escapes are ASCII-only, matching the upstream source contract.
	The caller supplies the index and position immediately after the backslash,
	then advances its own cursor to nextIndex. Invalid input throws at that position;
	decoded newlines do not change the source cursor's line number.
 */
function read(input:{source:String, offset:Int, position:HxPos}):HxDecodedStringEscape {
	var cursor = input.offset;
	function take():Int {
		final value = input.source.charCodeAt(cursor++);
		return value == null ? -1 : value;
	}
	function invalid():HxParseError
		return new HxParseError("Invalid string escape sequence", input.position);
	function digit(character:Int):Int {
		return character >= 48
			&& character <= 57 ? character - 48 : character >= 65
			&& character <= 70 ? character - 55 : character >= 97 && character <= 102 ? character - 87 : -1;
	}
	function hex(count:Int):Int {
		var value = 0;
		for (_ in 0...count) {
			final part = digit(take());
			if (part < 0)
				throw invalid();
			value = (value << 4) | part;
		}
		return value;
	}
	final kind = take();
	final value = switch kind {
		case 34 | 39 | 92: kind;
		case 110: 10;
		case 114: 13;
		case 116: 9;
		case 120:
			final code = hex(2);
			if (code > 127)
				throw invalid();
			code;
		case 117:
			var code = 0;
			if (input.source.charCodeAt(cursor) == 123) {
				cursor++;
				var count = 0;
				while (true) {
					final character = take();
					if (character == 125)
						break;
					final part = digit(character);
					if (part < 0 || code > (0x10ffff >> 4))
						throw invalid();
					code = (code << 4) | part;
					count++;
				}
				if (count == 0)
					throw invalid();
			} else
				code = hex(4);
			if (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff))
				throw invalid();
			code;
		case 48 | 49 | 50 | 51:
			var code = kind - 48;
			for (_ in 0...2) {
				final part = take() - 48;
				if (part < 0 || part > 7)
					throw invalid();
				code = (code << 3) | part;
			}
			if (code > 127)
				throw invalid();
			code;
		case _: throw invalid();
	};
	// Decode UTF-8 through the standard byte boundary instead of host-specific addChar behavior.
	final count = value < 0x80 ? 1 : value < 0x800 ? 2 : value < 0x10000 ? 3 : 4;
	final bytes = haxe.io.Bytes.alloc(count);
	if (count == 1)
		bytes.set(0, value);
	else {
		bytes.set(0, (count == 2 ? 0xc0 : count == 3 ? 0xe0 : 0xf0) | (value >> (6 * (count - 1))));
		for (index in 1...count)
			bytes.set(index, 0x80 | ((value >> (6 * (count - index - 1))) & 0x3f));
	}
	return {value: bytes.toString(), nextIndex: cursor};
}
