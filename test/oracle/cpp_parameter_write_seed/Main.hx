/** Parameter writes affect this invocation; captures share its selected storage. */
class Main {
	static function replace(value:Int, next:Int):Int {
		return value = next;
	}

	static function mask(value:Int):Int {
		value &= 63;
		return value;
	}

	static function effects(value:Int):Int {
		return value &= (value = 3);
	}

	static function update(value:Int):Int {
		final before = value++;
		final after = --value;
		return before * 100 + after * 10 + value;
	}

	static function flip(value:Bool):Bool {
		return value = !value;
	}

	static function captured(value:Int):Int {
		final change = () -> {
			value += 2;
			return value;
		};
		value = 3;
		if (change() != 5)
			throw "captured parameter did not share its write";
		return value;
	}

	static function nullable(value:Null<Int>):Int {
		value = 5;
		value += 2;
		return value;
	}

	static function callable():Int {
		final change = (value:Int) -> {
			value &= 7;
			return value++;
		};
		return change(11);
	}

	static function main():Void {
		final original = 9;
		if (replace(original, 3) != 3 || original != 9)
			throw "parameter assignment changed caller storage";
		if (mask(67) != 3 || effects(6) != 2)
			throw "compound parameter write changed sequencing";
		if (update(7) != 777)
			throw "parameter update changed prefix or postfix result";
		if (flip(true) || !flip(false))
			throw "Boolean parameter assignment changed its result";
		if (captured(9) != 5 || callable() != 3)
			throw "parameter capture or callable transport changed";
		final absent:Null<Int> = null;
		if (nullable(absent) != 7 || absent != null)
			throw "nullable parameter write changed caller storage";
		if (new ParameterOwner().replace(8) != 4)
			throw "instance parameter write changed its result";
	}
}

/** Instance calls keep their receiver distinct from source parameter slots. */
class ParameterOwner {
	public function new() {}

	public function replace(value:Int):Int {
		value = 4;
		return value;
	}
}
