/**
	Classifies the spelling of an unsuffixed Haxe integer literal.

	Why
	- Upstream Haxe 4.3.7 types an unsuffixed decimal literal as `Int` only when
	  its value fits the signed 32-bit range. A wider literal such as
	  `2147483648` is a `Float` with the exact value. The lexer used to call
	  `Std.parseInt` and keep `0` when the host could not represent the value,
	  so a native program printed `0` for `2147483648` without any error.
	- `Std.parseInt` also depends on the host. The same compiler runs under the
	  Haxe interpreter and as native OCaml, which has wider integers. This
	  module reads the digits itself, so classification is the same on every
	  host.

	What
	- `decimal` returns an `Int` value for digits that fit the signed 32-bit
	  range, and null for wider digits. The caller then reads the text as a
	  `Float`.
	- `hexadecimal` returns the 32-bit `Int` with the literal's bits, so
	  `0xFFFFFFFF` is `-1`, as upstream does. It returns null for a literal
	  wider than 32 bits, which upstream rejects as "Invalid hexadecimal
	  integer".

	Both functions take normalized text: digit separators removed, and no sign
	or suffix. The lexer reads `-2147483648` as a negation of `2147483648`; the
	parser folds that one spelling back into the minimum Int (see
	`HxParser.parseUnaryExpr`).
**/
class HxIntegerLiteral {
	/** The largest decimal magnitude of a signed 32-bit Int, as digits. */
	static inline final MAX_INT_DIGITS = "2147483647";

	/**
		The value of unsigned decimal `digits` when it fits the signed 32-bit Int
		range, or null when it does not (the literal is then a `Float`). Returns
		null for text that is not all decimal digits.
	**/
	public static function decimal(digits:String):Null<Int> {
		if (!isDecimalDigits(digits))
			return null;
		var start = 0;
		while (start < digits.length - 1 && digits.charCodeAt(start) == "0".code)
			start++;
		final significant = digits.substr(start);
		if (significant.length > MAX_INT_DIGITS.length || (significant.length == MAX_INT_DIGITS.length && significant > MAX_INT_DIGITS))
			return null;
		var value = 0;
		for (index in 0...significant.length)
			value = value * 10 + (significant.charCodeAt(index) - "0".code);
		return value;
	}

	/** Whether `text` is one or more decimal digits and nothing else. */
	public static function isDecimalDigits(text:String):Bool {
		if (text.length == 0)
			return false;
		for (index in 0...text.length) {
			final code = text.charCodeAt(index);
			if (code < "0".code || code > "9".code)
				return false;
		}
		return true;
	}

	/**
		The 32-bit Int with the bits of `text`, which starts with `0x` or `0X`.
		Returns null when the literal has no digits, has a non-hex digit, or has
		more than 8 digits. Like upstream, leading zeros count: `0x000000001` is
		rejected even though its value fits.
	**/
	public static function hexadecimal(text:String):Null<Int> {
		final significant = text.substr(2);
		if (significant.length == 0 || significant.length > 8)
			return null;
		var value = 0;
		for (index in 0...significant.length) {
			final digit = hexDigit(significant.charCodeAt(index));
			if (digit < 0)
				return null;
			value = (value << 4) | digit;
		}
		return value;
	}

	static function hexDigit(code:Int):Int {
		return if (code >= "0".code && code <= "9".code) code - "0".code else if (code >= "a".code && code <= "f".code) code - "a".code + 10 else
			if (code >= "A".code
			&& code <= "F".code) code
			- "A".code + 10 else -1;
	}
}
