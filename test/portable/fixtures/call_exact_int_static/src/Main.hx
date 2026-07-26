/** Executable proof that direct-call arguments run once in Haxe source order. */
class Main {
	static function sourceValue():Int {
		Sys.println("argument");
		return 41;
	}

	static function firstValue():Int {
		Sys.println("first");
		return 1;
	}

	static function secondValue():Int {
		Sys.println("second");
		return 2;
	}

	static function throwingFirst():Int {
		Sys.println("throw-first");
		throw "stop";
	}

	static function shouldNotRun():Int {
		Sys.println("second-should-not-run");
		return 2;
	}

	static function main():Void {
		final result = Arithmetic.increment(sourceValue());
		Sys.println("result=" + result);
		Sys.println("two=" + Arithmetic.add(firstValue(), secondValue()));
		final recovered = try {
			Arithmetic.add(throwingFirst(), shouldNotRun());
		} catch (_:Dynamic) {
			-1;
		};
		Sys.println("caught=" + recovered);
		Sys.println("instance=" + new Counter().increment(5));
	}
}
