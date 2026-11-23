/**
	A method body binds an untyped parameter before a recursive call passes it a wider value. Haxe
	4.3.7 types the body in order, so `switch (s)` binds `s` to `Item`, and the later
	`show(inner)` with `inner:Null<Item>` unifies without widening it
	(`haxe.CallStack.itemToString`, where the pattern variable even shadows the parameter).
**/
enum Item {
	Leaf(name:String);
	Pos(inner:Null<Item>, line:Int);
}

/** The observed operations take an untyped `s`; the patterns bind it to `Item`. **/
class Ops {
	public static function show(s):String {
		return switch (s) {
			case Leaf(name): name;
			case Pos(inner, line): (inner != null ? show(inner) : "") + ":" + line;
		};
	}

	public static function shadowed(s):String {
		return switch (s) {
			case Leaf(name): name;
			case Pos(s, line): (s != null ? shadowed(s) : "") + "/" + line;
		};
	}
}

class Main {
	static function main() {
		Sys.println(Ops.show(Pos(Pos(Leaf("x"), 1), 2)));
		Sys.println(Ops.shadowed(Pos(Leaf("y"), 3)));
		Sys.println(Ops.show(Pos(null, 4)));
	}
}
