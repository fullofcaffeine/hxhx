class Box {
	public function new() {}
}

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

	static function word(label:String, value:Null<String>):Null<String> {
		Sys.print("[" + label + "]");
		return value;
	}

	static function box(label:String, value:Box):Box {
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

		final intEqual = count(1) == count(2);
		Sys.println(" int equal " + intEqual);
		final floatDiffer = side("M", 1.5) != side("N", 1.5);
		Sys.println(" float differ " + floatDiffer);
		final textEqual = word("S", "a") == word("T", "a");
		Sys.println(" text equal " + textEqual);
		final shared = new Box();
		final sameBox = box("U", shared) == box("V", shared);
		Sys.println(" same box " + sameBox);
		final nullText = word("W", null) == word("X", null);
		Sys.println(" null text " + nullText);
		final nullInt = maybe("Y", null) != maybe("Z", 3);
		Sys.println(" null int " + nullInt);

		// Generated-text checks: an immutable local needs no binding, a mutable one does.
		final fixedLabel = "fixed";
		Sys.println(fixedLabel + step("m"));
		var runningLabel = "run";
		runningLabel = runningLabel + "!";
		Sys.println(runningLabel + step("n"));

		var w = 1;
		Sys.println("postfix " + Std.string(w++) + " " + Std.string(w));
		Sys.println("nested " + Std.string((w += 1) * 10) + " " + Std.string(w));
		var widened:Float = 3;
		Sys.println(widened + 0.25);
	}
}
