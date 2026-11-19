/**
	Omitted inputs used in comparisons and range bounds take their types from that use, as in
	Haxe 4.3.7. The operations live in their own class, declared before `Main`, so that calls
	from `main` cannot supply the evidence.
**/
class Ops {
	public static function equalsInt(value)
		return value == 1;

	public static function differsString(value)
		return value != "x";

	public static function lessFloat(value)
		return value < 1.5;

	public static function lessPair(left, right)
		return left < right;

	public static function atLeastString(value)
		return value >= "m";

	public static function equalsArray(value, other:Array<Int>)
		return value == other;

	public static function equalsDynamic(value, other:Dynamic)
		return value == other;

	public static function equalsPair(left, right)
		return left == right;

	public static function nullCheck(value) {
		if (value == null)
			return 0;
		return 1;
	}

	public static function nullFallback(first, second) {
		if (second == null)
			return first;
		return second;
	}

	public static function range(count) {
		var total = 0;
		for (i in 0...count)
			total += i;
		return total;
	}

	public static function codes(lengths, pos, count) {
		final tmp = [0, 0, 0, 0];
		for (i in 0...count) {
			final length = lengths[i + pos];
			if (length != 0) {
				final next = tmp[length - 1];
				tmp[length - 1] = next + 1;
			}
		}
		return tmp[0] + tmp[1];
	}
}

class Main {
	static function main() {
		Sys.println(Ops.equalsInt(1));
		Sys.println(Ops.differsString("y"));
		Sys.println(Ops.lessFloat(2.5));
		Sys.println(Ops.lessPair(1, 2));
		Sys.println(Ops.atLeastString("z"));
		Sys.println(Ops.range(4));
		Sys.println(Ops.codes([1, 2, 0, 1], 0, 4));
	}
}
