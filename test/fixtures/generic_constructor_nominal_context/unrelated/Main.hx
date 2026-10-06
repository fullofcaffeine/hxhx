interface Reader<T> {
	public function get(value:T):T;
}

class Cell<T> {
	public function new(value:T) {}

	public function get(value:T):T {
		return value;
	}
}

class Main {
	static function make():Reader<String> {
		return new Cell("seed");
	}

	static function main():Void {
		Sys.println(make().get("value"));
	}
}
