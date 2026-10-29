/** Methods exercise one shared static location through ordinary and escaped calls. */
class Main {
	static var value:Int;
	static var held:Dynamic;

	public static function seed(input:Int):Void {
		value = input;
		Other.value = input + 10;
	}

	public static function read():Int {
		return value + Other.value;
	}

	public static function escaped():Void->Int {
		return function():Int {
			return value;
		};
	}

	public static function update(effect:Void->Int):Int {
		return value = effect();
	}

	public static function keep(effect:Void->Dynamic):Dynamic {
		return held = effect();
	}

	public static function get():Dynamic {
		return held;
	}

	public static function shadow(value:Int):Int {
		return value;
	}

	/** Both bare and qualified fields keep their own update result and stored value. */
	public static function postIncrement():Int {
		return value++;
	}

	public static function preIncrement():Int {
		return ++value;
	}

	public static function postDecrement():Int {
		return Other.value--;
	}

	public static function preDecrement():Int {
		return --Other.value;
	}
}

/** A second same-named field must receive distinct storage. */
class Other {
	public static var value:Int;
}
