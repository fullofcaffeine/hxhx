/** Exercise the real Int64 provider's runtime predicate with unrelated values. */
class Main {
	/** Dynamic is required by the standard predicate; it stays at this test boundary. */
	static function check(value:Dynamic):Bool {
		return haxe.Int64.isInt64(value);
	}

	static function main():Void {
		Sys.println(check(haxe.Int64.make(1, 2)));
		Sys.println(check(haxe.Int64.ofInt(0)));
		Sys.println(check(null));
		Sys.println(check(2));
		Sys.println(check("2"));
		Sys.println(check([1, 2]));
	}
}
