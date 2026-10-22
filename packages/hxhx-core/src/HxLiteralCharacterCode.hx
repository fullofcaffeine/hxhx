/** The literal-only compiler operation either yields one Unicode scalar or a source error. */
enum HxLiteralCharacterCodeResult {
	NotApplicable;
	Character(value:Int);
	InvalidLiteral;
}

/**
	Recognize a direct string literal's .code without evaluating its receiver.
	UTF-8 bytes make the result independent of the compiler host's string indexing.
	Parentheses, concatenation, and variables remain ordinary field access.
 */
function resolve(expression:HxExpr):HxLiteralCharacterCodeResult {
	return switch expression {
		case EField(EString(text), "code"):
			final bytes = haxe.io.Bytes.ofString(text);
			if (bytes.length == 0 || bytes.length > 4)
				return InvalidLiteral;
			final first = bytes.get(0);
			final width = first < 0x80 ? 1 : first >= 0xc2
				&& first <= 0xdf ? 2 : first >= 0xe0 && first <= 0xef ? 3 : first >= 0xf0 && first <= 0xf4 ? 4 : 0;
			if (width != bytes.length || width == 0)
				return InvalidLiteral;
			var value = first & (width == 1 ? 0x7f : width == 2 ? 0x1f : width == 3 ? 0xf : 7);
			for (index in 1...width) {
				final next = bytes.get(index);
				if (next < 0x80 || next > 0xbf)
					return InvalidLiteral;
				value = (value << 6) | (next & 0x3f);
			}
			if ((width == 2 && value < 0x80) || (width == 3 && value < 0x800) || (width == 4 && value < 0x10000) || value > 0x10ffff
				|| (value >= 0xd800 && value <= 0xdfff)) InvalidLiteral; else Character(value);
		case _: NotApplicable;
	};
}
