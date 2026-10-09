import custom.Std as CustomStd;

/** Runtime type arguments are ordinary values, evaluated once in source order. */
class Main {
	static function value():Child {
		Sys.println("value");
		return new Child();
	}

	static function target():Class<Parent> {
		Sys.println("target");
		return Parent;
	}

	static function main():Void {
		final child = new Child();
		var selected:Class<Parent> = Parent;
		Sys.println(Std.isOfType(child, Child));
		Sys.println(Std.isOfType(child, selected));
		Sys.println(Std.isOfType(child, Other));
		Sys.println(Std.isOfType(new Parent(), Child));
		Sys.println(Std.isOfType(value(), target()));
		Sys.println(Std.isOfType([1], Array));
		Sys.println(Std.isOfType("text", String));
		Sys.println(Std.isOfType(null, selected));
		Sys.println(Std.isOfType(child, null));
		Sys.println(Aliased.check(child));
		Sys.println(CustomStd.isOfType(child, selected));
	}
}

/** A concrete parent provides an independent inheritance contract. */
class Parent {
	public function new() {}
}

/** An ordinary subclass must match its parent without sharing object identity. */
class Child extends Parent {}

/** An unrelated type must not match the child. */
class Other {
	public function new() {}
}
