/** Mirrors related object bounds carried through a class-valued argument. */
class Main {
	static function requireObject<T:{}, S:T>(value:T, kind:Class<S>):S {
		return cast value;
	}

	static function forward<A:{}, B:A>(value:A, kind:Class<B>):B {
		return requireObject(value, kind);
	}

	static function main():Void {
		final value = forward(new Box(), Box);
		Sys.println(value.label);
	}
}

/** Gives the returned type and runtime observer a concrete object identity. */
class Box {
	public final label:String = "class";

	public function new() {}
}
