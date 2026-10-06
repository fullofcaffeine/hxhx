interface Reader<T> {
	public function get(value:T):T;
}

class Cell<T> implements Reader<T> {
	public function new(value:T) {}

	public function get(value:T):T {
		return value;
	}
}

class Main {
	static function make():Reader<String> {
		return new Cell(1);
	}

	static function main():Void {
		Sys.println(make().get("value"));
	}
}
