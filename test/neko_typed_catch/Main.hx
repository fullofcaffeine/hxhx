/** Observes typed exception wrapping independently of String runtime operations. */
class Main {
	static function fail():Void {
		throw "problem";
	}

	static function main():Void {
		try {
			fail();
		} catch (error:haxe.Exception) {
			Sys.println("message:" + error.message);
		}
		final message = try {
			fail();
			"unreachable";
		} catch (error:haxe.Exception) {
			error.message;
		};
		Sys.println("expression:" + message);
		// Dynamic is the language-defined raw catch boundary. Compare immediately
		// with the concrete thrown value instead of letting it enter domain code.
		try {
			fail();
		} catch (raw:Dynamic) {
			Sys.println(raw == "problem" ? "raw-preserved" : "raw-changed");
		}
		try {
			throw 17;
		} catch (text:String) {
			Sys.println("wrong-string-catch");
		} catch (number:Int) {
			Sys.println("integer:" + number);
		}
	}
}
