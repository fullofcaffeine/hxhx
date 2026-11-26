enum abstract Kind(Int) to Int {
	var First = 1;
}

abstract Wrapped(Int) from Int to Int {}

class Base {
	public function new() {}
}

class Sub extends Base {}

/**
	A later argument of a generic call reaches T through a cast (haxe_ocaml-587vc). Upstream Haxe
	4.3.7 binds T from the first argument and unifies each later argument with it, through an
	abstract's casts, Any, subclassing and a Dynamic type argument.
**/
class Main {
	static function same<T>(a:T, b:T):Bool
		return a == b;

	static function main() {
		final wrapped:Wrapped = 1;
		final any:Any = 1;
		final base:Base = new Sub();
		Sys.println([
			same(1, First),
			same(1, wrapped),
			same(wrapped, 1),
			same(1, any),
			same(base, new Sub()),
			same(Type.resolveClass("Main"), Main)
		].join(","));
	}
}
