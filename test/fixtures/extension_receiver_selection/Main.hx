using Main.BoxTools;
using Main.TextTools;

/**
	Static extension selection skips a candidate whose first parameter does not accept the receiver,
	as upstream Haxe 4.3.7 does (haxe_ocaml-cd3jc): the later `using` is tried first.
**/
class Box {
	public function new() {}
}

class BoxTools {
	public static function describe(b:Box):String
		return "box";
}

class TextTools {
	public static function describe(s:String):String
		return "text";
}

class Main {
	static function main() {
		Sys.println(new Box().describe() + " " + "x".describe());
	}
}
