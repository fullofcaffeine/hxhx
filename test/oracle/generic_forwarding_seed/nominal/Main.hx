/** A caller's concrete bound can prove both an inherited class and an interface. */
class Main {
	static function requireObject<T:Base & Named>(value:T):T {
		return value;
	}

	static function forward<U:Child>(value:U):U {
		return requireObject(value);
	}

	static function main():Void {
		Sys.println(forward(new Child()).name());
	}
}

/** Supplies the nominal half of the required bound. */
class Base {
	public function new() {}
}

/** Supplies the interface half of the required bound. */
interface Named {
	public function name():String;
}

/** Satisfies both relationships without changing the forwarder's inferred type. */
class Child extends Base implements Named {
	public function new() {
		super();
	}

	public function name():String {
		return "nominal";
	}
}
