enum Shape {
	Dot;
	Circle(radius:Int);
}

enum Color {
	Red;
	Green;
	Blue;
}

class Main {
	static function colorName(c:Color):String
		return switch c {
			case Red: "red";
			case Green: "green";
			case Blue: "blue";
		}

	static function shapeName(s:Shape):String
		return switch s {
			case Dot: "dot";
			case Circle(r): "circle " + r;
		}

	static function main() {
		final green:Dynamic = Green;
		final castColor:Color = cast green;
		Sys.println("cast=" + colorName(castColor));
		final assigned:Color = green;
		Sys.println("assigned=" + colorName(assigned));
		final circle:Dynamic = Circle(4);
		final castShape:Shape = cast circle;
		Sys.println("shape=" + shapeName(castShape));
		final maybe:Null<Color> = cast green;
		Sys.println("nullable=" + (maybe == null ? "null" : colorName(maybe)));
	}
}
