/**
	Methods of one class that refer to each other, through calls or as
	first-class values, in either declaration order.
 */
class Main {
	final prefix:String;

	public function new(prefix:String) {
		this.prefix = prefix;
	}

	function earlier(v:String):String {
		return prefix + v;
	}

	/** Captures one method declared before it and one declared after it. */
	function captureBoth(values:Array<String>):String {
		return values.map(earlier).join(",") + "|" + values.map(later).join(",");
	}

	function later(v:String):String {
		return v + prefix;
	}

	/** Mutual recursion: `isEven` calls `isOdd`, which is declared after it. */
	function isEven(n:Int):Bool {
		return n == 0 ? true : isOdd(n - 1);
	}

	function isOdd(n:Int):Bool {
		return n == 0 ? false : isEven(n - 1);
	}

	/** Captures a static method declared after this static caller. */
	static function shoutAll(values:Array<String>):String {
		return values.map(shout).join(",");
	}

	static function shout(v:String):String {
		return v + "!";
	}

	static function main() {
		final m = new Main("-");
		Sys.println(m.captureBoth(["a", "b"]));
		Sys.println(m.isEven(4) + " " + m.isOdd(4) + " " + m.isEven(7));
		Sys.println(shoutAll(["x", "y"]));
	}
}
