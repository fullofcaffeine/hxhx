/**
	A local inferred from a class type expression reaches the class's static members
	(haxe_ocaml-wzpy5). Upstream Haxe 4.3.7 types `var s = Something` as the class's statics, so
	`s.somefunc()` is a static call with an Int result.
**/
class Something {
	public static var count = 0;

	public static function somefunc()
		return 42;

	public static function twice(x:Int):Int
		return x * 2;
}

class Main {
	static var calls = 0;

	static function same<T>(a:T, b:T):Bool
		return a == b;

	static function getCls() {
		calls++;
		return Something;
	}

	static function main() {
		var s = Something;
		final fn = s.somefunc;
		Something.count = 5;
		final direct:Int = s.somefunc();
		final viaValue:Int = fn();
		final doubled:Int = s.twice(21);
		final counted:Int = s.count;
		Sys.println(same(direct, 42) + " " + same(viaValue, 42) + " " + doubled + " " + counted);
		// A receiver with side effects keeps today's path (a dynamic call).
		Sys.println("via call " + getCls().somefunc());
	}
}
