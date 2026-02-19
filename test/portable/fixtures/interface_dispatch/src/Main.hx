interface IFoo {
	public function foo():Int;
}

class Base implements IFoo {
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
		final i:IFoo = new Child();
		Sys.println("foo=" + i.foo());
		Sys.println("OK interface_dispatch");
	}
}
