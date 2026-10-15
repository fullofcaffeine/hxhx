/** Check search calls through real String declarations and ordinary user methods. */
class Main {
	static var effects:Int = 0;
	static var initial:Int = "abcabc".indexOf("bc", 2);

	/** Native observers collect or throw between these authored operand calls. */
	public static function boundary(value:Void->String, needle:Void->String, start:Void->Null<Int>):Int {
		return value().indexOf(needle(), start());
	}

	public static function shadow(value:Shadow):Int {
		return value.indexOf("bc", 2);
	}

	static function receiver():String {
		effects = effects * 10 + 1;
		return "abcabc";
	}

	static function needle():String {
		effects = effects * 10 + 2;
		return "bc";
	}

	static function start():Int {
		effects = effects * 10 + 3;
		return 2;
	}

	static function main():Void {
		if (initial != 4 || "abcabc".indexOf("bc") != 1 || "abcabc".indexOf("bc", null) != 1)
			throw "initialization or default start";
		if ("aaaa".indexOf("aa", 1) != 1 || "abc".indexOf("missing") != -1)
			throw "overlapping or absent search";
		if (receiver().indexOf(needle(), start()) != 4 || effects != 123)
			throw "operand order";
		effects = 0;
		receiver().indexOf(needle(), start());
		if (effects != 123)
			throw "discarded operand order";
		if (shadow(new Shadow()) != 73)
			throw "ordinary user method dispatch";
		#if cpp
		if ("Aé😀Z😀".indexOf("Z") != 4 || "Aé😀Z😀".indexOf("😀", 3) != 5)
			throw "native UTF-16 positions";
		#end
	}
}

/** A same-named method must retain its own body and instance initialization. */
class Shadow {
	var initial:Int = "abcabc".indexOf("bc", 2);

	public function new() {}

	public function indexOf(needle:String, ?start:Int):Int {
		if (initial != 4)
			throw "instance initialization";
		return 73;
	}
}
