/** Primitive joins must preserve native formatting and evaluate both operands exactly once. */
class Main {
	static var effects:Int = 0;

	/** Native observers supply allocating or throwing callbacks at these exact authored operands. */
	public static function boundary(values:Void->Array<Int>, separator:Void->String):String {
		return values().join(separator());
	}

	public static function shadow(value:Shadow):String {
		return value.join("|");
	}

	static function receiver():Array<Int> {
		effects = effects * 10 + 1;
		return [1, -2, 0];
	}

	static function separator():String {
		effects = effects * 10 + 2;
		final allocation = ["::"];
		return allocation[0];
	}

	static function main():Void {
		final empty:Array<Int> = [];
		if (empty.join("::") != "")
			throw "empty join";
		if ([1].join("::") != "1")
			throw "singleton join";
		if (receiver().join(separator()) != "1::-2::0" || effects != 12)
			throw "ordered join";
		if ([true, false].join("|") != "true|false")
			throw "boolean join";
		if (["a", null, "", "é"].join("|") != "a|null||é")
			throw "string join";
		final nullable:Array<Null<Int>> = [1, null, -2];
		if (nullable.join("|") != "1|null|-2")
			throw "nullable join";
		if (["a", "b"].join("") != "ab")
			throw "empty separator";
		if (["a", "b", "c"].join(null) != "abc")
			throw "null separator";
		// This explicit erased boundary checks the existing native Boolean-array
		// recovery contract. Only these known primitive values enter the view.
		final mixed:Array<Dynamic> = [0, 1, null, "x"];
		final erased:Dynamic = mixed;
		final recovered:Array<Bool> = erased;
		if (recovered.join("|") != "false|true|false|false")
			throw "recovered Boolean join";
		effects = 0;
		receiver().join(separator());
		if (effects != 12)
			throw "discarded join";
	}
}

/** A same-named user method must not select the standard Array binding. */
class Shadow {
	public function new() {}

	public function join(separator:String):String
		return separator;
}
