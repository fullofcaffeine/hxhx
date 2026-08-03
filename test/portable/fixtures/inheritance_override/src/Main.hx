class Base {
	public function new() {}

	public function foo():Int {
		return 1;
	}

	/** Returns through an early String branch so virtual dispatch tests result ownership. */
	public function label(value:Int):String {
		if (value == 0)
			return "base-zero";
		return "base-other";
	}

	/** Prints one base marker and leaves before the later marker on the early path. */
	public function visit(value:Int):Void {
		Sys.println("base-void-before");
		if (value == 0)
			return;
		Sys.println("base-void-after");
	}
}

class Child extends Base {
	public function new() {
		super();
	}

	override public function foo():Int {
		return 2;
	}

	/** Keeps the same source contract while proving that the child result stays separate. */
	override public function label(value:Int):String {
		if (value == 0)
			return "child-zero";
		return "child-other";
	}

	/** Keeps virtual dispatch observable while exercising a payloadless early return. */
	override public function visit(value:Int):Void {
		Sys.println("child-void-before");
		if (value == 0)
			return;
		Sys.println("child-void-after");
	}
}

class Main {
	static function main() {
		final b:Base = new Child();
		Sys.println("foo=" + b.foo());
		final base:Base = new Base();
		final child:Base = new Child();
		Sys.println("base0=" + base.label(0));
		Sys.println("base1=" + base.label(1));
		Sys.println("child0=" + child.label(0));
		Sys.println("child1=" + child.label(1));
		base.visit(0);
		base.visit(1);
		child.visit(0);
		child.visit(1);
		Sys.println("OK inheritance_override");
	}
}
