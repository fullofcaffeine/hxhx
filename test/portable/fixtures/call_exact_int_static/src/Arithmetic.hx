/**
	Provides the first one- and two-argument callable shapes owned by the plan.
**/
class Arithmetic {
	public static function increment(value:Int):Int {
		Sys.println("callee");
		return value + 1;
	}

	public static function add(left:Int, right:Int):Int {
		Sys.println("two-callee");
		return left * 10 + right;
	}

	public static function identity<T>(value:T):T {
		return value;
	}
}
