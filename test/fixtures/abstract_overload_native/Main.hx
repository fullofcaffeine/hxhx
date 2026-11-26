/**
	A Stage3-native program with an overloaded abstract constructor. The compile path keeps the
	first overload only (haxe_ocaml-95co6), so this program uses that one.
**/
abstract Cells(Array<Int>) {
	extern overload public inline function new(length:Int) {
		this = [];
		for (_ in 0...length)
			this.push(1);
	}

	extern overload public inline function new(length:Int, value:Int) {
		this = [];
		for (_ in 0...length)
			this.push(value);
	}

	public inline function count():Int
		return this.length;
}

class Main {
	static function main() {
		Sys.println(new Cells(3).count());
	}
}
