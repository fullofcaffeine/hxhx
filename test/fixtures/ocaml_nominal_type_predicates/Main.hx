import Main.Child as RenamedChild;

/** Class membership follows private instance identity, including inherited interfaces. */
class Main {
	static var initialized:Bool = Std.isOfType(new Child(), Parent);

	static function observed(value:Dynamic):Dynamic {
		Sys.println("read");
		return value;
	}

	static function acceptsAny(value:Any):Bool
		return Std.isOfType(value, Parent);

	static function main():Void {
		var child = new Child();
		var value:Dynamic = child;
		Sys.println(initialized);
		Sys.println(value is Parent);
		Sys.println(Std.isOfType(value, Child));
		Sys.println(Std.isOfType(value, Parent));
		Sys.println(Std.isOfType(value, Marker));
		Sys.println(Std.isOfType(value, (RenamedChild)));
		Sys.println(Std.isOfType(new Parent(), Child));
		Sys.println(Std.isOfType(new Other(), Parent));
		Sys.println(Std.isOfType(null, Parent));
		Sys.println(Std.isOfType(0, Parent));
		Sys.println(Std.isOfType(true, Parent));
		Sys.println(Std.isOfType("text", Parent));
		Sys.println(Std.isOfType([1], Parent));
		var forged:Dynamic = {__hx_type: "Parent"};
		Sys.println(Std.isOfType(forged, Parent));
		Sys.println(Std.isOfType(observed(value), Parent));
		Sys.println(acceptsAny(value));
		Sys.println(Std.isOfType(1, NativeNamed));
		Sys.println(Std.isOfType(new NativeNamed(), NativeNamed));
	}
}

/** The inherited interface belongs to the same compiled class graph. */
interface Marker {}

/** The concrete parent supplies inherited membership. */
class Parent implements Marker {
	public function new() {}
}

/** The child retains its own identity and its parent's interface membership. */
class Child extends Parent {
	public function new() {
		super();
	}
}

/** A separate generated class must not match the parent. */
class Other {
	public function new() {}
}

/** A target-native public name retains the exact source class identity. */
@:native("external.NativeNamed")
class NativeNamed {
	public function new() {}
}
