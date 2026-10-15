/** Observe native Haxe search positions without reading its implementation. */
class IndexOfReference {
	static function observe(label:String, text:String, needle:String, ?start:Int):Void {
		try
			Sys.println(label + "=" + text.indexOf(needle, start))
		catch (error:haxe.Exception)
			Sys.println(label + "=throw");
	}

	static function main():Void {
		// Native Haxe crashes for this unspecified negative bound. Keep the
		// reproduction opt-in so it cannot hide the remaining observations.
		if (Sys.args().indexOf("--minimum") >= 0) {
			observe("minimum", "abc", "a", -2147483647 - 1);
			return;
		}
		observe("ascii", "abcabc", "bc");
		observe("offset", "abcabc", "bc", 2);
		observe("overlap", "aaaa", "aa", 1);
		observe("empty", "abc", "", 2);
		observe("empty-end", "abc", "", 3);
		observe("empty-past", "abc", "", 4);
		observe("empty-huge", "abc", "", 2147483647);
		observe("absent", "abc", "z");
		observe("past", "abc", "a", 2147483647);
		observe("empty-text", "", "");
		observe("empty-text-past", "", "", 1);
		observe("null-text", null, "a");
		observe("null-text-empty", null, "");
		observe("null-needle", "abc", null);
		observe("null-needle-offset", "abc", null, 2);
		observe("null-needle-past", "abc", null, 99);
		observe("null-both", null, null);
		observe("null-start", "abc", "b", null);
		observe("negative", "abc", "a", -1);
		observe("unicode-bmp", "Aé😀Z😀", "é");
		observe("unicode-pair", "Aé😀Z😀", "😀");
		observe("unicode-after", "Aé😀Z😀", "Z");
		observe("unicode-low-start", "Aé😀Z😀", "😀", 3);
		observe("unicode-empty", "Aé😀Z😀", "", 3);
		observe("unicode-mixed", "Aé😀Z😀", "😀Z");
		observe("nul", "a\x00bc\x00", "\x00", 2);
		observe("nul-suffix", "a\x00bc\x00", "bc\x00");
	}
}
