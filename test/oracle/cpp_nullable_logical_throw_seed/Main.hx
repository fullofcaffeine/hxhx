/** A selected logical operand throws before negation or its surrounding branch can finish. */
class Main {
	static var effects:Int = 0;

	static function condition(value:Null<Bool>):Null<Bool> {
		effects = 1;
		return value;
	}

	static function fail():Bool {
		if (effects != 1)
			throw "logical operand order changed";
		throw "selected operand";
	}

	public static function run():Void {
		if (!(condition(true) && fail()))
			throw "negation completed after throw";
		throw "selected throw was skipped";
	}

	static function main():Void
		run();
}
