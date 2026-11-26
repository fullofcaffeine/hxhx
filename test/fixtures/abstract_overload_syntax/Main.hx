/**
	An abstract with two same-name overloads, as `haxe.ds.Vector` declares its constructors.
	Haxe 4.3.7 keeps both fields.
**/
abstract Cells(Array<Int>) {
	extern overload public inline function new(length:Int) {
		this = [for (_ in 0...length) 0];
	}

	extern overload public inline function new(length:Int, value:Int) {
		this = [for (_ in 0...length) value];
	}

	extern overload public inline function sum():Int {
		var total = 0;
		for (value in this)
			total += value;
		return total;
	}

	extern overload public inline function sum(scale:Int):Int {
		var total = 0;
		for (value in this)
			total += value * scale;
		return total;
	}

	public var length(get, never):Int;

	inline function get_length():Int
		return this.length;
}

class Main {
	static function main() {
		final zeros = new Cells(2);
		final sevens = new Cells(3, 7);
		Sys.println(zeros.length + " " + sevens.length + " " + sevens.sum() + " " + sevens.sum(2));
	}
}
