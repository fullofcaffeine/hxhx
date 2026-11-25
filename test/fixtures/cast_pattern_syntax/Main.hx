/**
	Class-value case patterns as Haxe 4.3.7 parses them: `case cast Array:` keeps the `ECast` in the
	syntax tree.
**/
class Main {
	static function kind(value:Dynamic):String {
		return switch (Type.getClass(value)) {
			case cast Array: "array";
			case cast String: "string";
			case _: "other";
		}
	}

	static function main() {
		Sys.println(kind([1]) + " " + kind("a") + " " + kind(new Main()));
	}

	function new() {}
}
