/** A failed initializer must leave construction before its body can execute. */
class Main {
	public static function run():Void {
		new Failing();
		throw "continued";
	}

	static function main():Void {
		run();
	}
}

/** Reverse declaration order retains an allocated field before the later initializer throws. */
class Failing {
	public var value:Int = throw "initializer";
	public var held:Payload = new Payload();

	public function new() {
		throw "constructor";
	}
}

/** A managed child must become unreachable when construction unwinds. */
class Payload {
	public function new() {}
}
