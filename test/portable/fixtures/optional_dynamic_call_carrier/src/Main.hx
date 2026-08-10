typedef OptionalDynamicStringCallback = (?value:Dynamic) -> String;

/** A reference value used to prove that Dynamic keeps an object payload. */
class Marker {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

/** Functions whose trailing optional parameter uses Haxe's Dynamic carrier. */
class OptionalDynamicCalls {
	public static function describe(?value:Dynamic):String {
		return value == null ? "null" : Std.string(value);
	}

	public static function readsReference(expectedId:Int, ?value:Dynamic):Bool {
		return Std.isOfType(value, Marker) && (cast value : Marker).id == expectedId;
	}

	public static function callback():OptionalDynamicStringCallback {
		return describe;
	}
}

/** Exercises omitted and supplied values through the same optional boundary. */
class Main {
	static function main():Void {
		final marker = new Marker(7);
		Sys.println("omitted=" + OptionalDynamicCalls.describe());
		Sys.println("explicit-null=" + OptionalDynamicCalls.describe(null));
		Sys.println("bool=" + OptionalDynamicCalls.describe(true));
		Sys.println("int=" + OptionalDynamicCalls.describe(42));
		Sys.println("string=" + OptionalDynamicCalls.describe("haxe"));
		Sys.println("reference=" + OptionalDynamicCalls.readsReference(7, marker));
		Sys.println("function=" + OptionalDynamicCalls.callback()(99));
	}
}
