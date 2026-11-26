abstract Box(Int) {
	public function new(v:Int)
		this = v;

	@:op(A * B) static function scale<T:Int>(a:Box, b:T):Box
		return new Box((cast a : Int) * b);
}

/** The type parameter keeps its constraint: a Float is not an Int, so no operator applies. */
class Wrong {
	static function main() {
		final box = new Box(2);
		final scaled = box * 1.5;
		Sys.println(scaled);
	}
}
