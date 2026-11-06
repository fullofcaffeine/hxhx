/**
	Known failing until PR #131 (Bead haxe_ocaml-nq65n) lands: static `@:isVar` properties.

	Stage3 on main stores a static field as an immutable OCaml value, so the
	setter's `return count = value` cannot store, and `count` stays 0. PR #131
	adds native static field storage; with it, this program matches upstream.
	The test requires that this fixture still differs from upstream; once it
	matches, fold these lines into `stage3_isvar_properties`.
**/
class Registry {
	@:isVar public static var count(get, set):Int = 0;

	static function get_count():Int {
		return count;
	}

	static function set_count(value:Int):Int {
		return count = value;
	}

	public static function bump():Void {
		count++;
	}
}

class Main {
	static function main():Void {
		Registry.count = 3;
		Sys.println("static: " + Registry.count);
		Registry.count++;
		Registry.count += 5;
		Registry.bump();
		Sys.println("static updates: " + Registry.count);
	}
}
