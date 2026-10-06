/** Constructor effects and transformed initialization must execute exactly once. */
class PrimitiveConstructorEffectsMain {
	static var calls = 0;

	static function input():Int {
		calls++;
		return 7;
	}

	static function main():Void {
		final result = new TransformedResult(input());
		Sys.println(result.read());
		Sys.println(calls);
		Sys.println(TransformedResult.effects);
	}
}

/** An argument passthrough cannot reproduce the authored constructor result. */
abstract TransformedResult(Int) {
	public static var effects = 0;

	public function new(value:Int) {
		effects++;
		this = value * 2 + 1;
		effects++;
	}

	public function read():Int {
		return this;
	}
}
