using Main.SortStringTools;
using Main.SortFloatTools;

/**
	With two `using` classes that provide `sorted`, the call uses the first candidate whose
	type-parameter constraint the receiver satisfies (haxe_ocaml-5l9ut).
**/
class SortStringTools {
	public static function sorted<T:String, A:Array<T>>(arr:A):String
		return "string";
}

class SortFloatTools {
	public static function sorted<T:Float, A:Array<T>>(arr:A):String
		return "float";
}

class Main {
	static function main() {
		Sys.println(["abc", "def"].sorted() + " " + [123, 456].sorted() + " " + [1.5].sorted());
	}
}
