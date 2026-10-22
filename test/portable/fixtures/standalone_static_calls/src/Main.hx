/** Verifies planned optional and effect-only calls during static initialization. */
class Main {
	static final omitted = Calls.optionalInt();
	static final supplied = Calls.optionalInt(5);
	static final afterEffect = {
		Calls.run();
		1;
	};

	static function main():Void {
		Sys.println(omitted);
		Sys.println(afterEffect);
		Sys.println(supplied);
	}
}

/** Ordinary Haxe methods keep the same optional and Void contracts in initializers. */
class Calls {
	public static function optionalInt(?value:Int):Int {
		return value == null ? -1 : value;
	}

	public static function run():Void {
		Sys.println("called");
	}
}
