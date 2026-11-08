/** Shared classes for the Dynamic downcast constraint cases. */
class Base {
	public function new() {}
}

class Sub extends Base {
	public function new() {
		super();
	}
}

class Sibling extends Base {
	public function new() {
		super();
	}
}
