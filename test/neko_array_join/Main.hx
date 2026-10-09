/** Makes the order and number of element conversions observable. */
class Piece {
	var value:String;

	public function new(value:String):Void {
		this.value = value;
	}

	public function toString():String {
		Sys.println("convert:" + value);
		return value;
	}
}

/** Compares array method lookup and element conversion with upstream Neko. */
class Main {
	static function main():Void {
		var values = ["left", "right"];
		var joined = try {
			values.join("|");
		} catch (error:Dynamic) {
			"unexpected";
		};
		Sys.println(joined);
		var empty:Array<String> = [];
		Sys.println("empty:" + empty.join("|"));
		Sys.println(["only"].join("|"));
		Sys.println([1, 2].join(":"));
		Sys.println(["a", null, "b"].join(":"));
		Sys.println([[1, 2], [3]].join(";"));
		Sys.println(values.join(null));
		Sys.println([new Piece("x"), new Piece("y")].join("|"));
	}
}
