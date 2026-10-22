class Box {
	public function new() {}
}

interface Face {}

class Implementer implements Face {
	public function new() {}
}

class Main {
	static function echo<T:{}>(value:T):T {
		return value;
	}

	static function main() {
		final value = echo((new Implementer() : Face));
	}
}
