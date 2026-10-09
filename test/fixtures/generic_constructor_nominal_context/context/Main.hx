interface Reader<T> {
	public function get(value:T):T;
}

class Cell<T> implements Reader<T> {
	public function new() {}

	public function get(value:T):T {
		return value;
	}
}

class Main {
	static function make():Reader<String> {
		return new Cell();
	}

	static function main():Void {
		Sys.println(make().get("value"));
	}
}
