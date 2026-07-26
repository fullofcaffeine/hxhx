/**
	Provides the first exact callable shape owned by the typed OCaml call plan.
**/
class Arithmetic {
	public static function increment(value:Int):Int {
		Sys.println("callee");
		return value + 1;
	}

	public static function add(left:Int, right:Int):Int {
		return left + right;
	}

	public static function identity<T>(value:T):T {
		return value;
	}
}
