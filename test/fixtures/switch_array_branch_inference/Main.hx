/**
	A switch expression whose branches mix complete arrays with an empty literal has the complete
	element type, as in Haxe 4.3.7 (`eval/_std/sys/ssl/Mbedtls.hx` builds its certificate paths this
	way). The operations live in their own class, declared before `Main`, so that calls from `main`
	cannot supply the evidence.
**/
class Ops {
	// The empty literal is the default branch.
	public static function total(name:String) {
		var paths = switch (name) {
			case "a": ["x", "yy"];
			case "b": ["zzz"];
			default: [];
		}
		var n = 0;
		for (path in paths)
			n += path.length;
		return n;
	}

	// The empty literal comes first.
	public static function sum(flag:Bool) {
		var items = switch (flag) {
			case true: [];
			case false: [1, 2];
		}
		var result = 0;
		for (item in items)
			result += item;
		return result;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.total("a"));
		Sys.println(Ops.total("q"));
		Sys.println(Ops.sum(true));
		Sys.println(Ops.sum(false));
	}
}
