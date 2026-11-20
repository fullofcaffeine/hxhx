/**
	An omitted input that receives a new container takes the container's element type from later
	uses, as in Haxe 4.3.7. The operations live in their own class, declared before `Main`, so
	that calls from `main` cannot supply the evidence.
**/
class Ops {
	// An optional input filled with `new Array()` when absent.
	public static function collect(?path) {
		if (path == null)
			path = new Array();
		path.push("x");
		return path.length;
	}

	// A required input replaced by a new array.
	public static function replace(items) {
		items = new Array();
		items.push(3);
		return items.length;
	}

	// An empty array literal instead of a constructor.
	public static function literal(?names) {
		if (names == null)
			names = [];
		names.push("a");
		return names.join(",");
	}

	// The shape of `haxe.xml.Check.makeError`: a recursive method that passes the input on.
	public static function trail(depth:Int, ?path) {
		if (path == null)
			path = new Array();
		if (depth == 0)
			return path.join("/");
		path.push("d" + depth);
		return trail(depth - 1, path);
	}
}

class Main {
	static function main() {
		Sys.println(Ops.collect());
		Sys.println(Ops.replace([]));
		Sys.println(Ops.literal());
		Sys.println(Ops.trail(3));
	}
}
