/** Ordinary arguments and results that must cross the shared target boundary unchanged. */
class Main {
	public static function choose(first:Int, second:Int):Int {
		final copy = first;
		return copy;
	}

	public static function logical(value:Bool):Bool
		return value;

	public static function equal(hx_left:Int, hx_right:Int):Bool
		return hx_left == hx_right;

	public static function different(first:Int, second:Int):Bool
		return first != second;

	public static function conjunction(first:Bool, second:Bool):Bool
		return first && second;

	public static function disjunction(first:Bool, second:Bool):Bool
		return first || second;

	public static function callComparison(first:Int, second:Int):Bool
		return choose(first, second) != first || choose(second, first) != second;

	public static function text(value:String):String
		return value;

	public static function invoke(hx_arg:Int, other:Int):Int
		return choose(choose(hx_arg, other), other);

	public static function scoped(value:Int):Int {
		{
			final value = 9;
			value;
		}
		return value;
	}

	public static function done():Void {
		return;
	}

	public static function branch(flag:Bool, first:Int, second:Int):Int
		return flag ? first : second;

	public static function branchBool(flag:Bool, first:Bool, second:Bool):Bool
		return flag ? first : second;

	public static function branchText(flag:Bool, first:String, second:String):String
		return flag ? first : second;

	public static function branchBlock(flag:Bool, first:Int, second:Int):Int
		return if (flag) {
			final value = first;
			value;
		} else {
			final value = second;
			value;
		};

	public static function nestedBranch(outer:Bool, inner:Bool, value:Int):Int
		return outer ? branch(inner, value, 17) : branch(inner, 29, value);

	public static function branchReturn(flag:Bool, first:Int, second:Int):Int {
		if (flag) {
			final value = first;
			return value;
		} else {
			return second;
		}
	}

	static function main():Void {
		choose(7, 9);
		logical(false);
		equal(3, 9);
		different(3, 9);
		conjunction(false, true);
		disjunction(true, false);
		callComparison(3, 9);
		text("hé\x00z");
		invoke(3, 5);
		scoped(8);
		done();
		branch(true, 3, 9);
		branchBlock(false, 3, 9);
		nestedBranch(false, true, 5);
		branchReturn(true, 7, 9);
	}
}
