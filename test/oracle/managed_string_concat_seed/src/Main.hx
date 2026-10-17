/** Observe primitive text and declaration-proven abstract integer conversions. */
class Main {
	static var missing:String;
	static var events:String = "";
	static var count:Int = 0;

	static function left():String {
		events = events + "L";
		count += 1;
		return "left";
	}

	static function right():Int {
		events = events + "R";
		count += 1;
		return 7;
	}

	/** Record one evaluation while returning a signed abstract value. */
	static function signed():haxe.Int32 {
		events = events + "I";
		count += 1;
		return -17;
	}

	static function main():Void {
		Sys.println("hello" + " world");
		Sys.println("value=" + 12);
		Sys.println(-12 + "=value");
		Sys.println("bool=" + true);
		Sys.println(false + "=bool");
		Sys.println("[" + missing + "]");
		Sys.println(left() + right());
		Sys.println(events);
		Sys.println(count);
		Sys.println("é" + "界");
		Sys.println("a\x00" + "b");
		Sys.println(2 + 3);
		Sys.println("same" == "same");
		Sys.println("same" != "other");
		final minimum:haxe.Int32 = -2147483648;
		final maximum:haxe.Int32 = 2147483647;
		Sys.println("min=" + minimum);
		Sys.println(maximum + "=max");
		events = "";
		count = 0;
		Sys.println(left() + signed());
		Sys.println(signed() + left());
		Sys.println(events);
		Sys.println(count);
		final wrapped:Count = 41;
		Sys.println("wrapped=" + wrapped);
		var appended = "append=";
		appended += maximum;
		Sys.println(appended);
	}
}

/** A user declaration must receive the same proven integer view as Int32. */
abstract Count(Int) from Int to Int {}
