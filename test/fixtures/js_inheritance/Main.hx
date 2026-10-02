/** Constructor calls preserve argument effects and inherited method dispatch. */
class Main {
	public static var created:Child;

	static function argument(value:String):String {
		Sys.println("arg-" + value);
		return value;
	}

	static function main():Void {
		final child = new Child(argument("one"), argument("two"));
		created = child;
		Sys.println(child.describe());
		final implicit = new ImplicitChild(argument("three"), argument("four"));
		Sys.println(implicit.describe());
		final grandchild = new ImplicitGrandchild(argument("five"));
		Sys.println(grandchild.describe());
		final generic = new GenericChild("generic");
		Sys.println(generic.get());
	}
}

/** The child appears before its parent to exercise declaration ordering. */
class Child extends Parent {
	public function new(first:String, second:String) {
		Sys.println("pre");
		super(first, second);
		Sys.println("post");
	}

	public override function describe():String {
		return super.describe() + ":child";
	}
}

/** The parent owns storage initialized by the child's explicit super operands. */
class Parent {
	var value:String;

	public function new(first:String, second:String = "default") {
		value = first + ":" + second;
		Sys.println("base:" + value);
	}

	public function describe():String {
		return value;
	}
}

/** An omitted constructor forwards the supplied operands to its parent. */
class ImplicitChild extends Parent {
	public override function describe():String {
		return super.describe() + ":implicit";
	}
}

/** Multiple implicit constructors preserve omission until the owning default runs. */
class ImplicitGrandchild extends ImplicitChild {
	public override function describe():String {
		return super.describe() + ":grand";
	}
}

/** The written generic parent must resolve to its emitted class provider. */
class GenericChild extends GenericParent<String> {
	public function new(value:String) {
		super(value);
	}
}

/** Storage and an inherited method retain the value supplied by the child. */
class GenericParent<T> {
	var value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function get():T {
		return value;
	}
}
