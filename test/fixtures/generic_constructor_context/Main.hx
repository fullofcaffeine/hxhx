/** A later call constrains the omitted type argument of an ordinary generic class. */
class Main {
	static function take(value:Box<String>):String {
		return "ok";
	}

	static function main():Void {
		final inferred = new Box();
		Sys.println(take(inferred));
		final explicit = new Box<String>();
		Sys.println(take(explicit));
	}
}

/** Framework-neutral generic constructor: no Map or target-specific API is involved. */
class Box<T> {
	public function new() {}
}
