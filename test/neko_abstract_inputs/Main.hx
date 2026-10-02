/** Deliberately accepts arbitrary values at a declared Dynamic storage boundary. */
abstract Box(Dynamic) from Dynamic {
	public function matches(value:String):Bool {
		return this == value;
	}

	public function holds(value:Payload):Bool {
		return this == value;
	}
}

/** A String input keeps its existing representation inside this abstract. */
abstract Text(String) from String {
	public function matches(value:String):Bool {
		return this == value;
	}
}

/** Gives the runtime observer an object whose identity must survive the conversion. */
class Payload {
	public function new() {}
}

/** Argument conversions must preserve values, declaration selection, and effects. */
class Main {
	static function produce():String {
		Sys.println("argument");
		return "text";
	}

	static function acceptBox(value:Box):Bool {
		return value.matches("text");
	}

	static function acceptText(value:Text):Bool {
		return value.matches("text");
	}

	static function retain(value:Box, expected:Payload):Bool {
		return value.holds(expected);
	}

	static function probe():Bool {
		return acceptBox(produce());
	}

	static function probeText():Bool {
		return acceptText("text");
	}

	static function main():Void {
		Sys.println(probe());
		Sys.println(probeText());
		final value = new Payload();
		Sys.println(retain(value, value));
	}
}
