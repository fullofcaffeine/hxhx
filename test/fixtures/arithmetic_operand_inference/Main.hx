/**
	Omitted inputs of `- * / %` take Int from their use, as in Haxe 4.3.7. The operations live in
	their own class, declared before `Main`, so that calls from `main` cannot supply the evidence.
**/
class Ops {
	public static function sub(value)
		return value - 1;

	public static function subFloat(value)
		return value - 1.5;

	public static function floatLeft(value)
		return 1.5 - value;

	public static function div(value)
		return value / 2;

	public static function mod(value)
		return value % 3;

	public static function mul(value)
		return value * 4;

	public static function pair(left, right)
		return left - right;

	public static function alias(value) {
		final copy = value;
		return copy - 1;
	}

	public static function dynamicPeer(value, other:Dynamic)
		return value - other;

	public static function explicit(value:Dynamic)
		return value - 1;

	public static function firstUse(value) {
		final result = value - 1;
		final widened:Float = value;
		return result + widened;
	}

	public static function unused(value)
		return 0;
}

class Main {
	static function main() {
		Sys.println(Ops.sub(5));
		Sys.println(Ops.subFloat(5));
		Sys.println(Ops.floatLeft(1));
		Sys.println(Ops.div(7));
		Sys.println(Ops.mod(7));
		Sys.println(Ops.mul(2));
		Sys.println(Ops.pair(9, 4));
		Sys.println(Ops.alias(3));
		Sys.println(Ops.dynamicPeer(10, 2.5));
		Sys.println(Ops.explicit(3));
		Sys.println(Ops.firstUse(2));
	}
}
