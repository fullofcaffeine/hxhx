class Box {
	public function new() {}
}

abstract Wrapped(Int) {
	public function new() {
		this = 7;
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
