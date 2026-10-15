/** Keep real String declarations and independently specified substring results in native execution. */
class Main {
	static var effects:Int = 0;
	static var initial:String = "abcdef".substr(1, 2);

	/** Observer callbacks collect or throw between these exact authored operands. */
	public static function boundary(value:Void->String, position:Void->Int, length:Void->Null<Int>):String {
		return value().substr(position(), length());
	}

	public static function shadow(value:Shadow):String {
		return value.substr(1, 2);
	}

	static function receiver():String {
		effects = effects * 10 + 1;
		return "abcdef";
	}

	static function position():Int {
		effects = effects * 10 + 2;
		return 1;
	}

	static function length():Int {
		effects = effects * 10 + 3;
		return 3;
	}

	static function main():Void {
		if (initial != "bc")
			throw "static initializer";
		if ("abcdef".substr(1, 3) != "bcd")
			throw "positive bounds";
		if ("abcdef".substr(-2) != "ef")
			throw "negative position";
		if ("abcdef".substr(-20, 3) != "abc")
			throw "clamped position";
		if ("abcdef".substr(2) != "cdef")
			throw "omitted length";
		if ("abcdef".substr(2, null) != "cdef")
			throw "null length";
		if ("abcdef".substr(2, 0) != "")
			throw "zero length";
		if ("abcdef".substr(20, 1) != "")
			throw "past end";
		if ("".substr(-3, 2) != "")
			throw "empty receiver";
		if ("abcdef".substr(2, 20) != "cdef")
			throw "clamped length";
		if ("Aé😀Z".substr(1, 1) != "é")
			throw "multibyte character";
		if (receiver().substr(position(), length()) != "bcd" || effects != 123)
			throw "operand order";
		effects = 0;
		receiver().substr(position(), length());
		if (effects != 123)
			throw "discarded operand order";
		#if cpp
		if ("abcdef".substr(0, -2) != "abcd" || "abcdef".substr(1, -2) != "bcde" || "abcdef".substr(2, -2) != "")
			throw "negative native lengths";
		if ("Aé😀Z".substr(2, 2) != "😀" || "Aé😀Z".substr(2, 1) != "�" || "Aé😀Z".substr(3, 1) != "�")
			throw "native UTF-16 indexing";
		effects = 0;
		final absent:Null<Int> = null;
		if ("abcdef".substr(absent, 2) != "ab")
			throw "native null position";
		final missing:String = null;
		if (missing.substr(position(), length()) != "" || effects != 23)
			throw "native null receiver";
		#end
		if (shadow(new Shadow()) != "ordinary")
			throw "ordinary method dispatch";
	}
}

/** A same-named method must retain ordinary class dispatch. */
class Shadow {
	var initial:String = "abcdef".substr(1, 2);

	public function new() {}

	public function substr(position:Int, ?length:Int):String {
		if (initial != "bc")
			throw "instance initializer";
		return "ordinary";
	}
}
