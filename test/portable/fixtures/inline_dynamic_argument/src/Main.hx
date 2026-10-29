/** Checks implicit casts inserted by inline calls and the original JSON use. */
class Main {
	static var calls:Int = 0;

	static function next():String {
		calls++;
		return "alpha";
	}

	static inline function forward(value:Dynamic):String {
		return Sink.describe(value);
	}

	static function main():Void {
		function namespace(parts:Array<String>):String {
			var value = "root";
			for (part in parts)
				value = value + "[" + haxe.Json.stringify(part) + "]";
			return value;
		}
		Sys.println(namespace(["alpha", "b\"eta"]));
		Sys.println("forward=" + forward(next()) + ",calls=" + calls);
		Sys.println("bool=" + forward(true));
		Sys.println("int=" + forward(17));
		Sys.println("null=" + forward(null));
	}
}
