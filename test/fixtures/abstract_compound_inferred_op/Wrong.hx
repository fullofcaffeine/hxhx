abstract A(Int) {
	public function new(i)
		this = i;

	public function get()
		return this;

	@:op(A + B) static function add(x:A, x2:Int)
		return x.get() + x2;
}

/** The base operator's result (Int) does not fit the destination (A): upstream reports `Int should be A`. */
class Wrong {
	static function main() {
		var a = new A(1);
		a += 1;
		Sys.println(a.get());
	}
}
