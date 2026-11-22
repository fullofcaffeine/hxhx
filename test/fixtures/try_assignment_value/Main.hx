/**
	A `try` expression on the right side of an ordinary assignment keeps both its successful value
	and its catch fallback, for a local and for a static field, as in Haxe 4.3.7.
	`value = try load() catch (error:Dynamic) fallback;` must not lose the `try`.
**/
class Loader {
	public static var cached:Int = 0;

	public static function load(ok:Bool):Int {
		if (!ok)
			throw "no";
		return 7;
	}
}

/** The observed operations take simple inputs; `fallback` is typed only through the `try`. **/
class Ops {
	public static function local(ok:Bool, fallback) {
		var value = 0;
		value = try Loader.load(ok) catch (error:Dynamic) fallback;
		return value;
	}

	public static function field(ok:Bool, fallback:Int) {
		Loader.cached = try Loader.load(ok) catch (error:Dynamic) fallback;
		return Loader.cached;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.local(true, 3));
		Sys.println(Ops.local(false, 3));
		Sys.println(Ops.field(true, 4));
		Sys.println(Ops.field(false, 4));
	}
}
