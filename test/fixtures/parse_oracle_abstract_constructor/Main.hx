/**
	Abstract constructors for the parse oracle's constructor rule: upstream's recorder sees them as
	`_new` inside a generated `var this:T; ...; return cast this;` wrapper.
**/
abstract Flags(Int) {
	public inline function new(i:Int)
		this = i;

	public inline function value():Int
		return this;
}

abstract Pair({a:Int, b:Int}) {
	public function new(a:Int, b:Int) {
		var total = a + b;
		this = {a: a, b: total};
	}

	public function sum():Int
		return this.b;
}

/** A plain class whose name looks like an implementation class: its `_new` is authored. **/
class Lookalike_Impl_ {
	public static function _new():Int {
		var x = 1;
		return x;
	}
}

class Main {
	static function main() {
		Sys.println(new Flags(3).value() + " " + new Pair(1, 2).sum() + " " + Lookalike_Impl_._new());
	}
}
