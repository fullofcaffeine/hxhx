/**
	`f.bind(...)` on a function value, as Haxe 4.3.7 types it (haxe_ocaml-kee1x): bound arguments
	are evaluated once, `_` keeps a parameter open, and a trailing optional parameter is omitted.
**/
class Counter {
	public var base:Int;

	public function new(base:Int)
		this.base = base;

	public function add(a:Int, b:Int):Int
		return base + a + b;
}

class Main {
	static var evaluations = 0;

	static function add(a:Int, b:Int):Int
		return a + b;

	static function label(text:String, ?suffix:String):String
		return suffix == null ? text : text + suffix;

	static function call(f:() -> Int):Int
		return f();

	static function next():Int
		return ++evaluations;

	static function main() {
		final plus1 = add.bind(1);
		final secondFixed = add.bind(_, 2);
		final counter = new Counter(10);
		final method = counter.add.bind(5);
		counter.base = 20;
		final once = add.bind(next());
		Sys.println(plus1(2) + " " + secondFixed(3) + " " + method(1) + " " + call(add.bind(4, 5)));
		Sys.println(once(1) + " " + once(1) + " " + evaluations + " " + label.bind("a")());
	}
}
