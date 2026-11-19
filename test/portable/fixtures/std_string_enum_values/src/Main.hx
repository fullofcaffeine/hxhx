enum Color {
	Red;
	Green;
	Blue(n:Int);
}

class Main {
	static function label(c:Null<Color>):String
		return "color:" + c;

	static function main() {
		final green = Green;
		final blue = Blue(2);
		Sys.println(Std.string(green));
		Sys.println(Std.string(blue));
		Sys.println("value=" + green + "," + blue);
		final maybe:Null<Color> = Red;
		final none:Null<Color> = null;
		Sys.println(Std.string(maybe));
		Sys.println(Std.string(none));
		Sys.println(label(Blue(3)));
		Sys.println(label(null));
	}
}
