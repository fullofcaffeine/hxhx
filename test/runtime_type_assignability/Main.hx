/** Root and diamond-shaped interface relationships are independent of constructors. */
interface Root {}
interface Left extends Root {}
interface Right extends Root {}
interface Diamond extends Left extends Right {}

class Parent implements Diamond {
	public function new() {}
}

class Child extends Parent {
	public function new() {
		super();
	}
}

class Unrelated {
	public function new() {}
}

/** Observe exact class and interface membership through ordinary Haxe syntax. */
class Main {
	static function main():Void {
		final child = new Child();
		Sys.println(child is Child);
		Sys.println(child is Parent);
		Sys.println(child is Diamond);
		Sys.println(child is Left);
		Sys.println(child is Right);
		Sys.println(child is Root);
		Sys.println(child is Unrelated);
		Sys.println(new Parent() is Child);
		Sys.println(new Unrelated() is Root);
	}
}
