/**
	A compound assignment reuses an abstract's binary operator whose result is inferred
	(haxe_ocaml-bps3m). Upstream Haxe 4.3.7 rewrites `a += 1` as `a = a + 1` and selects
	`@:op(A + B)`, whose result type comes from its body.
**/
abstract A(Int) {
	public function new(i)
		this = i;

	public function get()
		return this;

	@:op(A + B) static function add(x:A, x2:Int)
		return new A(x.get() + x2);
}

class Main {
	static function main() {
		var a = new A(1);
		a += 1;
		a += 40;
		Sys.println(a.get());
	}
}
