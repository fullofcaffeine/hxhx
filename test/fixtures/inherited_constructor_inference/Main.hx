/**
	A class without its own constructor infers its type arguments through the inherited one, as in
	upstream Haxe 4.3.7 (haxe_ocaml-q076l).
**/
class C2<T> {
	var t:T;

	public function new(t) {
		this.t = t;
	}
}

class SC2<T> extends C2<Array<T>> {
	public function get()
		return t;
}

class Deeper<T> extends SC2<T> {}

class Parent<T> {
	public var value:T;
	public var count:Int;

	public function new(value:T, count:Int) {
		this.value = value;
		this.count = count;
	}
}

class Child<T> extends Parent<Array<T>> {}

class Main {
	static function main() {
		final first:Int = new SC2([1]).get()[0];
		final text:String = new Deeper(["d"]).get()[0];
		final explicit:Float = new SC2<Float>([1.5]).get()[0];
		final child = new Child([2, 3], 2);
		final second:Int = child.value[1];
		Sys.println(first + " " + text + " " + explicit + " " + second + " " + child.count);
	}
}
