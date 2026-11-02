/**
	The portable spelling of a Float switch pattern (`HxSwitchPattern.PFloat`).

	Why
	- Source spellings such as `.5`, `1e3` or `2147483648` are valid Haxe but
	  not valid Float literals in every target language (OCaml rejects `.5`,
	  C# reads `2147483648` as an integer). A pattern keeps one normalized
	  spelling with a leading digit and a `.` or exponent, so each backend can
	  print it directly.
	- The text, not a host Float, is the pattern's identity: printing a Float
	  with `Std.string` depends on the host and can round.

	What
	- `of(".5", 0.5, false)` is `"0.5"`, `of("1e3", 1000.0, true)` is
	  `"-1e3"`, `of("2147483648", ..., false)` is `"2147483648.0"`.
	- `value(text)` reads the number back for equality checks.
**/
class HxFloatPatternText {
	public static function of(written:Null<String>, value:Float, negative:Bool):String {
		var text = written == null ? Std.string(value) : written;
		if (StringTools.startsWith(text, "."))
			text = "0" + text;
		if (text.indexOf(".") < 0 && text.indexOf("e") < 0 && text.indexOf("E") < 0)
			text += ".0";
		return negative ? "-" + text : text;
	}

	public static function value(text:String):Float {
		return Std.parseFloat(text);
	}
}
