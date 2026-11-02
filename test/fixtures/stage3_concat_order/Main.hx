class Main {
	static function step(name:String):String {
		Sys.print("[" + name + "]");
		return name;
	}

	static function count(n:Int):Int {
		Sys.print("[" + n + "]");
		return n;
	}

	static function side(label:String, value:Float):Float {
		Sys.print("[" + label + "]");
		return value;
	}

	static function maybe(label:String, value:Null<Int>):Null<Int> {
		Sys.print("[" + label + "]");
		return value;
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

		final quotient = side("I", 9) / side("J", 2);
		Sys.println(" divide " + quotient);
		final intQuotient = count(9) / count(2);
		Sys.println(" int divide " + intQuotient);
		final less = side("E", 1) < side("F", 2);
		Sys.println(" less " + less);
		final atMost = count(3) <= count(3);
		Sys.println(" at most " + atMost);
		final nullableLess = maybe("G", 4) > maybe("H", 5);
		Sys.println(" nullable " + nullableLess);
		final sum = side("K", 0.5) + side("L", 0.25);
		Sys.println(" sum " + sum);

		var w = 1;
		Sys.println("postfix " + Std.string(w++) + " " + Std.string(w));
		Sys.println("nested " + Std.string((w += 1) * 10) + " " + Std.string(w));
		var widened:Float = 3;
		Sys.println(widened + 0.25);
	}
}
