enum Color {
	Red;
	Green;
	Blue(level:Int);
}

typedef MaybeColor = Null<Color>;

class Main {
	static function show(color:Null<Color>):String
		return color == null ? "null" : switch (color : Color) {
			case Red: "Red";
			case Green: "Green";
			case Blue(level): "Blue(" + level + ")";
		}

	static function pass(color:Null<Color>):Null<Color>
		return color;

	static function make():Null<Color>
		return (Blue(2) : Null<Color>);

	static function main() {
		var local:Null<Color> = (Green : Null<Color>);
		Sys.println("local=" + show(local));
		Sys.println("argument=" + show(pass((Red : Null<Color>))));
		Sys.println("return=" + show(make()));
		var alias:MaybeColor = (Blue(3) : MaybeColor);
		Sys.println("alias=" + show(alias));
		var captured:Null<Color> = (Green : Null<Color>);
		var get = () -> captured;
		Sys.println("capture=" + show(get()));
		var record:{v:Null<Color>} = {v: (Red : Null<Color>)};
		Sys.println("field=" + show(record.v));
		var observed:Dynamic = local;
		Sys.println("dynamic=" + (observed == null ? "null" : "set"));
		var none:Null<Color> = null;
		Sys.println("none=" + show(none));
	}
}
