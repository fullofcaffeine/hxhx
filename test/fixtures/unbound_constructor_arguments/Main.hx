/**
	A constructed class's type parameter that nothing in the body gives a type stays open in upstream
	Haxe 4.3.7 (a monomorph); hxhx closes it to its declared bound, or Dynamic (haxe_ocaml-6a7w5).
	Evidence anywhere in the body still binds it.
**/
class Foo<T> {
	public var val(get, null):T;

	public function new() {}

	function get_val():T
		return null;
}

class Dummy<T> {
	public function new(arg:Null<T>) {}
}

class Shape {
	public function new() {}

	public function name()
		return "shape";
}

class Holder<T:Shape> {
	public function new() {}

	public function get():Null<T>
		return null;
}

class Main {
	static function flatMap<B>(a:List<B>):Int {
		var count = 0;
		for (x in a)
			count++;
		return count;
	}

	static function main() {
		final foo = new Foo();
		final empty = new List();
		new Dummy(null);
		final numbers = new List();
		numbers.add(1);
		final first:Int = numbers.first();
		final shape:Null<Shape> = new Holder().get();
		final list = new Array();
		Sys.println((foo.val == null) + " " + flatMap(empty) + " " + first + " " + (shape == null) + " " + list.length);
	}
}
