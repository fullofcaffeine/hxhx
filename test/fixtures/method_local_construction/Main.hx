/** Method-local allocations and length temporaries remain local through native emission. */
class Main {
	public var length:Int;

	public function new(length:Int) {
		this.length = length;
	}

	public function copy():Main {
		var r = new Main(length);
		var len = length;
		r.length = len;
		return r;
	}

	static function main() {
		var original = new Main(3);
		var copied = original.copy();
		if (original == copied)
			throw "copy reused its source";
		copied.length = 7;
		Sys.println(original.length);
		Sys.println(copied.length);
	}
}
