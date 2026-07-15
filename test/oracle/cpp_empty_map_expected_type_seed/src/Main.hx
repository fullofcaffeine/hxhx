/** Unrelated generic constructor control for expected call-argument typing. **/
class ExpectedBox<T> {
	public var value:Null<T>;

	public function new() {}

	public function set(value:T):Void {
		this.value = value;
	}
}

/** Non-generic zero-argument constructor control. **/
class ExpectedPlain {
	public final value:Int;

	public function new() {
		value = 7;
	}
}

/**
	Upstream Haxe 4.3.7 oracle for expected typing of empty constructors.

	An unhinted zero-argument generic constructor may receive its type arguments
	from a later call parameter. Populated and explicit Maps remain controls for
	their existing inference paths.
**/
class Main {
	static function acceptMap(value:Map<Int, String>):String {
		value.set(7, "seven");
		return value.get(7);
	}

	static function acceptBox(value:ExpectedBox<String>):String {
		value.set("box");
		return value.value;
	}

	static function main():Void {
		final inferred = new Map();
		Sys.println(acceptMap(inferred));
		Sys.println(inferred.get(7));

		final populated = new Map();
		populated.set("name", 3);
		Sys.println(populated.get("name"));

		final typedMap = new Map<Int, String>();
		typedMap.set(4, "four");
		Sys.println(typedMap.get(4));

		final box = new ExpectedBox();
		Sys.println(acceptBox(box));
		Sys.println(new ExpectedPlain().value);
	}
}
