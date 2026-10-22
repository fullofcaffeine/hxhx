interface Reader<A, B> {
	public function get(value:A, other:B):A;
}

class Cell<X, Y> implements Reader<Y, X> {
	public function new() {}

	public function get(value:Y, other:X):Y {
		return value;
	}
}

class Main {
	static function make():Reader<String, Int> {
		return new Cell();
	}

	static function main():Void {
		Sys.println(make().get("value", 1));
	}
}
