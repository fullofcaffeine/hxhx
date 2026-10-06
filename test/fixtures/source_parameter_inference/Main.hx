/** Exercise written, expected, and body-derived parameter types through real callbacks. */
class Main {
	static function apply(callback:Int->Int):Int {
		return callback(5);
	}

	static function adapt(callback:Int->Int) {
		return function(value) {
			return callback(value);
		};
	}

	static function main():Void {
		Sys.println(apply((value:Int) -> value + 10));
		Sys.println(apply(value -> value + 10));
		Sys.println(apply((value:Dynamic) -> value + 10));
		final adapted = adapt(value -> value + 10);
		Sys.println(adapted(5));
	}
}
