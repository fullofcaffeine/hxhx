/**
	Regex literals as Haxe 4.3.7 parses them: the syntax tree keeps `EConst(CRegexp(pattern, flags))`,
	and the lexer decodes `\/`, `\r`, `\n` and `\t` in the pattern while keeping other escapes.
**/
class Main {
	static function literals(text:String):Bool {
		var plain = ~/[0-9]+/;
		var flagged = ~/ab+c/gi;
		return plain.match(text) || flagged.match(text);
	}

	static function escapes(text:String):String {
		var slashes = ~/^(https?:\/\/)?([a-z.]+)$/;
		var controls = ~/[\r\n\t]+/g;
		var kept = ~/\d+\.\w*\$/;
		return controls.replace(slashes.replace(text, "$2"), " ") + (kept.match(text) ? "!" : "");
	}

	static function receiver(text:String):String
		return ~/[aeiou]/g.replace(text, "*");

	static function main() {
		Sys.println(literals("x123") + " " + literals("ABBC") + " " + literals("zz"));
		Sys.println(escapes("http://haxe.org") + "|" + escapes("a\tb"));
		Sys.println(receiver("haxe"));
	}
}
