/** Any is intentional at the heterogeneous catch boundary; each handler observes the received value. */
class Main {
	static function main():Void {
		try {
			throw "raw";
		} catch (value:Any) {
			Sys.println("text=" + Std.string(value));
		}
		try {
			throw 23;
		} catch (value:Any) {
			Sys.println("number=" + Std.string(value));
		}
		final original = new haxe.Exception("original");
		try {
			throw original;
		} catch (value:Any) {
			Sys.println("exception=" + (value == original));
		}
		final wrapper = new haxe.ValueException("wrapped");
		try {
			throw wrapper;
		} catch (value:Any) {
			Sys.println("wrapper=" + (value == wrapper));
		}
		try {
			throw "fallback";
		} catch (value:custom.Any) {
			Sys.println("wrong-shadow-handler");
		} catch (value:Dynamic) {
			// Dynamic is the explicit catch-all used to observe rejection of the user class.
			Sys.println("shadow=" + Std.string(value));
		}
	}
}
