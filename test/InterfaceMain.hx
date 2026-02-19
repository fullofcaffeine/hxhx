interface IFoo {
	public function foo():Int;
}

class Foo implements IFoo {
	public function new() {}

	public function foo():Int {
		return 1;
	}
}

class InterfaceMain {
	static function main() {
		final f = new Foo();
		f.foo();
	}
}
