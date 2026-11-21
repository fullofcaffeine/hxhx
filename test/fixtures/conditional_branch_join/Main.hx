/**
	A conditional expression joins an open branch with the other branch's type, as in Haxe 4.3.7:
	`flag ? "a" : fallback` gives `fallback` the type String, in either branch order. The
	operations live in their own class, declared before `Main`, so that calls from `main` cannot
	supply the evidence.
**/
class Ops {
	public static function elseOpen(flag:Bool, fallback)
		return flag ? "a" : fallback;

	public static function thenOpen(flag:Bool, preferred)
		return flag ? preferred : 2;

	public static function method(flag:Bool, text:String, other)
		return flag ? text.toUpperCase() : other;

	public static function ifExpression(flag:Bool, fallback) {
		final picked = if (flag) 1.5 else fallback;
		return picked * 2;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.elseOpen(true, "b"));
		Sys.println(Ops.elseOpen(false, "b"));
		Sys.println(Ops.thenOpen(true, 7));
		Sys.println(Ops.method(true, "up", "down"));
		Sys.println(Ops.ifExpression(false, 4.0));
	}
}
