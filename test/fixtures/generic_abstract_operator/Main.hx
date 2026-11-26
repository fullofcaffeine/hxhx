/**
	An abstract operator declared with a type parameter (haxe_ocaml-tnnxn). Upstream Haxe 4.3.7
	gives the operator function's type parameters constrained monomorphs and binds them to the
	operand types: UInt's `equalsInt<T:Int>(a:UInt, b:T)` serves `u == 3` and `3 == u`.
**/
abstract Meters(Float) from Float to Float {
	@:op(A + B) static function addNumber<T:Float>(a:Meters, b:T):Meters
		return (a : Float) + b;
}

class Main {
	static function main() {
		final u:UInt = 3;
		final m:Meters = 1.5;
		final sum:Meters = m + 2;
		Sys.println([u == 3, 3 == u, u != 4, u == 3.0].join(",") + " " + (sum : Float));
	}
}
