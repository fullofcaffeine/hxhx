class Box {
	public function new() {}
}

abstract Wrapped(Box) to Box {
	public function new() {
		this = new Box();
	}
}

class Main {
	static function echo<T:{}>(value:T):T {
		return value;
	}

	static function main() {
		final value = echo(new Wrapped());
	}
}
