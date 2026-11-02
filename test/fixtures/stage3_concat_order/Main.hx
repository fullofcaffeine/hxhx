class Main {
	static function step(name:String):String {
		Sys.print("[" + name + "]");
		return name;
	}

	static function count(n:Int):Int {
		Sys.print("[" + n + "]");
		return n;
	}

	static function main():Void {
		Sys.println(" calls " + step("a") + step("b") + step("c"));
		Sys.println(" mixed " + count(1) + step("x") + count(2));
		final joined = step("p") + step("q") + count(3);
		Sys.println(" joined " + joined);
		var text = "s";
		text += step("t") + count(4);
		Sys.println(" update " + text);

		var ratio:Float = 0.5;
		Sys.println(ratio + 0.25);
		Sys.println(ratio * 3 + 0.25);
		final whole = 2;
		Sys.println(whole + 3);
		Sys.println(whole + 3 + "x");
		Sys.println("x" + whole + 3);
		Sys.println(ratio + 0.25 + " units");
		Sys.println(count(6) + count(7));
		Sys.println("");
	}
}
