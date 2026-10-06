/** A constructor-free child must fail before control reaches its ancestor body. */
class Main {
	public static function run():Void {
		new Failing();
		throw "continued";
	}

	static function main():Void {
		run();
	}
}

/** The missing child constructor cannot suppress its own initialization effects. */
class Failing extends Base {
	public var value:Int = throw "initializer";
	public var held:Payload = new Payload();
}

/** Reaching this body would prove that the child's failure was skipped. */
class Base {
	public function new() {
		throw "constructor";
	}
}

/** Its lifetime ends when the child's later initializer throws. */
class Payload {
	public function new() {}
}
