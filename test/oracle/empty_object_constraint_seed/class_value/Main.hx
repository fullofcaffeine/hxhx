class Box {
	public function new() {}
}

enum Pick {
	One;
}

class Main {
	static function echo<T:{}>(value:T):T {
		return value;
	}

	static function main() {
		final value = echo(Box);
	}
}
