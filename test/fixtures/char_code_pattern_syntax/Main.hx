/**
	Character-code case patterns as Haxe 4.3.7 parses them: `case "x".code:` keeps the field access
	`"x".code` in the syntax tree, also inside or-patterns and array patterns.
**/
class Main {
	static function classify(c:Int):String {
		return switch (c) {
			case "a".code: "a";
			case " ".code | "\t".code | "\n".code: "space";
			case "\\".code: "backslash";
			case _: "other";
		}
	}

	static function pair(codes:Array<Int>):Bool {
		return switch (codes) {
			case ["2".code, "1".code]: true;
			case _: false;
		}
	}

	static function main() {
		Sys.println(classify("a".code) + " " + classify(" ".code) + " " + classify("\\".code) + " " + classify("z".code));
		Sys.println(pair(["2".code, "1".code]) + " " + pair([1, 2]));
	}
}
