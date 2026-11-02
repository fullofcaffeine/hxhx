import Shapes;

/** Valid downcast shapes that upstream Haxe accepts because no argument fixes the source type. */
class Main {
	static function main():Void {
		final dynamicBase:Dynamic = new Base();
		final dynamicSub:Dynamic = new Sub();
		final anyBase:Any = new Base();
		final base = new Base();
		final narrowed:Null<Sub> = Std.downcast(dynamicBase, Sub);
		trace(narrowed == null);
		trace(Std.downcast(dynamicSub, Sub) != null);
		trace(Std.downcast(anyBase, Sub) == null);
		trace(Std.downcast(null, Sub) == null);
		Std.downcast(base, cast null);
		Std.downcast(dynamicBase, cast null);
		Std.downcast(cast null, Sub);
		trace(Std.downcast(base, Base) == base);
		trace(open(dynamicSub, "text"));
		final anyNumber:Any = 3;
		trace(requireInt(anyNumber));
		trace(make(Base) != null);
		trace(pick(null, 5));
		trace(arrayOf(null, [5]));
		trace(arrayOf(null, []));
		trace(arrayOf(null, [null]));
		// As a statement: upstream accepts this, though a typed destination such as `:Any` makes it reject.
		arrayOf(null, anyNumber);
	}

	/** A null literal leaves `T` as a nullable monomorph, so upstream accepts `S:T` for any `S`. */
	static function pick<T:String, S:T>(value:T, fallback:S):S {
		return fallback;
	}

	/** A null `T` matches structurally inside `S:Array<T>`: here `T` is read as Int. */
	static function arrayOf<T, S:Array<T>>(value:T, fallback:S):S {
		return fallback;
	}

	/** Any satisfies every bound: its generic `@:to` conversion can produce an Int. */
	static function requireInt<T:Int>(value:T):T {
		return value;
	}

	/** Like `js.lib.Reflect.construct`, an omitted optional argument leaves `S` with no evidence. */
	static function make<T, S:T>(c:Class<T>, ?alternative:Class<S>):T {
		return Type.createInstance(c, []);
	}

	/** A user signature with the same dependent shape: `S:T` where `T` is only known as Dynamic. */
	static function open<T:{}, S:T>(value:T, fallback:S):S {
		return fallback;
	}
}
