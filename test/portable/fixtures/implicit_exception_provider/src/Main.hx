/** Exercises exception members used by generated catches, without naming ValueException. */
class Main {
	static function main():Void {
		try {
			throw "catalog-rejection";
		} catch (error:haxe.Exception) {
			Sys.println("wrapped=" + error.message);
		}

		final original = new haxe.Exception("existing");
		try {
			throw original;
		} catch (error:haxe.Exception) {
			Sys.println("identity=" + (error == original));
			Sys.println("message=" + error.message);
		}

		try {
			throw "raw";
		} catch (value:String) {
			Sys.println("raw=" + value);
		}
	}
}
