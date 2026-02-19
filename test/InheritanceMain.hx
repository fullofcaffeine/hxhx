class Base {
	public function new() {}

	public function foo():Int {
		return 1;
	}
}

class InheritanceMain extends Base {
	public function new() {
		super();
	}

	static function main() {
		final x = new InheritanceMain();
		x.foo();
	}
}
