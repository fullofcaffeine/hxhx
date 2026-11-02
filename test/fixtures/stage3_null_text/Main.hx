enum Color {
	Red;
	Rgb(r:Int, g:Int, b:Int);
}

class Holder {
	public var label:String;

	public function new() {}
}

class Main {
	static var staticText:String = null;

	static function maybe(flag:Bool):String {
		return flag ? "yes" : null;
	}

	static function count(flag:Bool):Null<Int> {
		return flag ? 3 : null;
	}

	static function main() {
		// Null Strings on either side of +.
		final nothing:String = maybe(false);
		final present = maybe(true);
		Sys.println("x=" + nothing);
		Sys.println(nothing + "=x");
		Sys.println("call " + maybe(false) + " " + maybe(true));
		Sys.println("static " + staticText);
		final holder = new Holder();
		Sys.println("field " + holder.label);
		Sys.println(present + nothing);
		// Null Strings through other text paths.
		Sys.println(nothing);
		Sys.println(Std.string(nothing));
		Sys.println('interpolated ${nothing}');
		final words:Array<String> = ["a", null, "b"];
		Sys.println(words.join(","));
		Sys.println(Std.string(words));
		// String += on a null local, as a statement and as a value.
		var s:String = null;
		s += "x";
		Sys.println(s);
		var t:String = null;
		final r = (t += "y");
		Sys.println(r + " " + t);
		var u = "start";
		u += nothing;
		Sys.println(u);
		// Null<Int> values in concatenation.
		final hello = "Hello";
		Sys.println("concat " + (hello.charCodeAt(9) + "a"));
		Sys.println("code " + hello.charCodeAt(0) + " " + hello.charCodeAt(9));
		Sys.println("count " + count(true) + " " + count(false));
		final missing:Null<Int> = null;
		Sys.println(missing + "!");
		// A parenthesized Int addition inside a concatenation stays arithmetic.
		final number = 41;
		Sys.println("sum " + (number + 1) + " " + ("(" + (number + 1) + ")"));
		// Enum values.
		Sys.println("e=" + Red);
		Sys.println("e=" + Rgb(1, 2, 3));
		final color = Rgb(4, 5, 6);
		Sys.println(Std.string(color) + " " + Std.string(Red));
		Sys.println([Red, Rgb(7, 8, 9)].join(" "));
		Sys.println(Std.string([Red, color]));
	}
}
