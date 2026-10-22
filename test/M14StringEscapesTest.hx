/** Check decoded UTF-8 bytes and source cursor ownership before parsing or typing. */
class M14StringEscapesTest {
	static function main():Void {
		final slash = String.fromCharCode(92);
		for (entry in [
			{escape: "u{1F600}", hex: "f09f9880"},
			{escape: "u00E9", hex: "c3a9"},
			{escape: "u{10FFFF}", hex: "f48fbfbf"},
			{escape: "u{000000041}", hex: "41"},
			{escape: "u0000", hex: "00"},
			{escape: "x00", hex: "00"},
			{escape: "x7F", hex: "7f"},
			{escape: "000", hex: "00"},
			{escape: "101", hex: "41"},
			{escape: "177", hex: "7f"},
			{escape: "n", hex: "0a"},
			{escape: "r", hex: "0d"},
			{escape: "t", hex: "09"},
			{escape: "\"", hex: "22"},
			{escape: "'", hex: "27"},
			{escape: slash, hex: "5c"}
		]) {
			for (quote in ['"', "'"]) {
				final source = quote + slash + entry.escape + quote;
				final lexer = new HxLexer(source + " next");
				switch lexer.next().kind {
					case TString(text, interpolate):
						if (haxe.io.Bytes.ofString(text).toHex() != entry.hex || interpolate != (quote == "'"))
							throw "decoded escape differs: " + source;
					case _:
						throw "escape did not produce a string: " + source;
				}
				final next = lexer.next();
				if (!next.kind.match(TIdent("next")) || next.pos.index != source.length + 1 || next.pos.line != 1 || next.pos.column != source.length + 2)
					throw "escape consumed the following token or changed its source position";
			}
		}
		for (escape in [
			"xE9",
			"x80",
			"xG0",
			"x0",
			"uD800",
			"uDFFF",
			"u{110000}",
			"u{}",
			"u{GG}",
			"u{41",
			"u041",
			"0",
			"08",
			"200",
			"377",
			"400",
			"b",
			"q"
		]) {
			for (quote in ['"', "'"]) {
				var rejected = false;
				try
					new HxLexer(quote + slash + escape + quote).next()
				catch (error:HxParseError) {
					if (error.pos.index != 2 || error.pos.line != 1 || error.pos.column != 3)
						throw "invalid escape lost its source position";
					rejected = true;
				}
				if (!rejected)
					throw "invalid escape accepted: " + escape;
			}
		}
		// Interpolation syntax is transported unchanged for the expression parser.
		final interpolation = new HxLexer("'" + "$" + "{value}'").next();
		switch interpolation.kind {
			case TString(text, true) if (text == "$" + "{value}"):
			case _:
				throw "escape decoding changed interpolation transport";
		}
		Sys.println("STRING_ESCAPES:PASS");
	}
}
