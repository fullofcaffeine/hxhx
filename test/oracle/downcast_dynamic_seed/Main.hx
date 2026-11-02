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
		trace(Std.downcast(base, Base) == base);
		trace(open(dynamicSub, "text"));
		final anyNumber:Any = 3;
		trace(requireInt(anyNumber));
		trace(make(Base) != null);
		trace(pick(null, 5));
	}

	/** A null literal leaves `T` as a nullable monomorph, so upstream accepts `S:T` for any `S`. */
	static function pick<T:String, S:T>(value:T, fallback:S):S {
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
