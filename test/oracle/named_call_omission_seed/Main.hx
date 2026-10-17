using Main.NamedCallExtensions;

/** Skipped method slots preserve default values and the order of the supplied expressions. */
class Main {
	static var effects:Int = 0;

	public function new() {}

	function instanceTake(value:Int = 4, tail:String):Int
		return tail == "tail" ? value : 0;

	function trailing(value:Int = 4):Int
		return value;

	static function receiver():Main {
		effects = effects * 10 + 1;
		return new Main();
	}

	static function take(value:Int = 4, tail:String):Int
		return tail == "tail" ? value : 0;

	static function prefix():String {
		effects = effects * 10 + 1;
		return "prefix";
	}

	static function tail():String {
		effects = effects * 10 + 2;
		return "tail";
	}

	static function flag():Bool {
		effects = effects * 10 + 3;
		return false;
	}

	static function collect(prefix:String, value:Int = 4, tail:String, ?flag:Bool):Int {
		if (flag == null)
			throw "supplied flag was omitted";
		if (flag)
			throw "supplied false value was replaced";
		if (prefix != "prefix" || tail != "tail")
			throw "supplied operands entered the wrong slots";
		return value;
	}

	static function main():Void {
		if (take("tail") != 4 || take(9, "tail") != 9)
			throw "middle omission lost its default or supplied value";
		if (collect(prefix(), tail(), flag()) != 4 || effects != 123)
			throw "argument effects changed count or order";
		effects = 0;
		if (receiver().instanceTake(tail()) != 4 || effects != 12)
			throw "instance omission changed receiver or operand effects";
		final instance = new Main();
		final absent:Null<Int> = null;
		if (instance.trailing() != 4 || instance.trailing(0) != 0 || instance.trailing(absent) != 4)
			throw "instance entry confused omission, zero, and nullable input";
		effects = 0;
		if (receiver().extensionTake(tail()) != 4 || effects != 12)
			throw "extension omission changed receiver or operand effects";
	}
}

/** The extension receiver is a separate first operand; only explicit arguments can be skipped. */
class NamedCallExtensions {
	public static function extensionTake(receiver:Main, value:Int = 4, tail:String):Int
		return tail == "tail" ? value : 0;
}
