/**
	A call argument converts through an abstract cast into a parameter that names the method's own
	type parameters, as in Haxe 4.3.7 (haxe_ocaml-uyvpx).
**/
abstract CustomArray(Array<Int>) from Array<Int> to Array<Int> {}
abstract Wrapped<T>(T) from T to T {}

abstract Lazy<T>(() -> T) {
	public function new(f)
		this = f;

	public function evaluate()
		return this();

	@:from static function ofConst<T>(c:T):Lazy<T>
		return new Lazy(function() return c);
}

abstract Rounded(Float) to Float {
	@:from public static function fromFloat(v:Float):Rounded
		return cast Math.round(v);
}

class Main {
	static function same<T>(a:Array<T>, b:Array<T>):Bool
		return a.length == b.length;

	static function lazy<A>(l:Lazy<A>):Lazy<A>
		return l;

	static function pair<T>(a:T, b:T):String
		return a + "," + b;

	static function main() {
		final list:CustomArray = [10];
		final wrapped:Wrapped<Array<Int>> = [0, 1];
		final readOnly:haxe.ds.ReadOnlyArray<Int> = [1, 2];
		Sys.println(same([10], list) + " " + Lambda.count(wrapped) + " " + Lambda.exists(readOnly, i -> i == 2));
		Sys.println(lazy(2).evaluate());
		Sys.println(pair((1.6 : Rounded), 1));
	}
}
