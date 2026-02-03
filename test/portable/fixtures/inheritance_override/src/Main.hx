class Base {
	public function new() {}

	public function foo():Int {
		return 1;
	}
}

class Child extends Base {
	public function new() {
		super();
	}

	override public function foo():Int {
		return 2;
	}
}

class Main {
	static function main() {
		final b:Base = new Child();
		Sys.println("foo=" + b.foo());
		Sys.println("OK inheritance_override");
	}
}

