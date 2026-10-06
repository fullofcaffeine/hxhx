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
	}
}
