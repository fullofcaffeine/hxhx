/** Array calls evaluate their receiver and argument once, in source order. */
class Main {
	static function receiver():Array<String> {
		Sys.println("receiver");
		return ["a", "b"];
	}

	static function mapper():String->String {
		Sys.println("mapper");
		return transform;
	}

	static function transform(value:String):String {
		Sys.println("element:" + value);
		return value + "!";
	}

	static function separator():String {
		Sys.println("separator");
		return ",";
	}

	static function main():Void {
		final values = receiver().map(mapper());
		Sys.println(values.join(separator()));
	}
}
