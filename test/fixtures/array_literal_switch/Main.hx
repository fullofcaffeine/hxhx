/**
	A switch on an array literal matches position by position, as in Haxe 4.3.7:
	`switch ([shape, paint])` with `case [Circle(r), Solid(c)]` binds `r` from `shape` and `c` from
	`paint`. haxe.macro.TypeTools switches on `[cf.kind, cf.type]` this way. The operations live
	in their own class, declared before `Main`, so that calls from `main` cannot supply the evidence.
**/
enum Shape {
	Circle(r:Int);
	Rect(w:Int, h:Int);
}

enum Paint {
	Solid(c:Int);
	Pattern(names:Array<String>);
}

class Ops {
	/** `limit` is an Int only when `r` and `w` keep their payload types. **/
	public static function wide(shape:Shape, paint:Paint, limit)
		return switch ([shape, paint]) {
			case [Circle(r), Solid(c)]: r > limit && c > 0;
			case [Rect(w, _), Pattern(names)]: w > limit && names.length > 0;
			case _: false;
		}

	/** `suffix` is a String only when `names` is an Array<String>. **/
	public static function labels(count:Int, paint:Paint, suffix)
		return switch ([count, paint]) {
			case [1, Pattern(names)]: [for (n in names) n + suffix];
			case _: [];
		}
}

class Main {
	static function main() {
		Sys.println(Ops.wide(Circle(2), Solid(1), 1));
		Sys.println(Ops.wide(Rect(3, 4), Pattern(["a", "b"]), 4));
		Sys.println(Ops.wide(Circle(1), Pattern([]), 0));
		Sys.println(Ops.labels(1, Pattern(["x", "y"]), "!").join(","));
		Sys.println(Ops.labels(2, Solid(3), "?").length);
	}
}
