import pk.Meter;
import pk.Res;

/**
	A type's `@:using` metadata adds static extensions to its values, as in Haxe 4.3.7:
	`result.resolve()` for `@:using(pk.Res.ResTools) enum Res<T>`. eval's `sys.thread.EventLoop`
	calls `LuvTimer.init(handle).resolve()` this way. The operations live in their own class,
	declared before `Main`, so that calls from `main` cannot supply the evidence.
**/
class Ops {
	/** `expected` is a String only when `resolve()` returns the payload type. **/
	public static function value(result:Res<String>, expected)
		return result.resolve() == expected;

	public static function ready(result:Res<Int>, flag)
		return result.isOk() == flag;

	/** The provider takes `Int`, the abstract's `to` type. **/
	public static function twice(other)
		return new Meter(21).doubled() == other;

	public static function local(text:String, suffix) {
		final kept = Res.Ok(text).resolve();
		return kept == suffix ? 1 : 0;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.value(Ok("hello"), "hello"));
		Sys.println(Ops.value(Ok("hello"), "none"));
		Sys.println(Ops.ready(Err("no"), false));
		Sys.println(Ops.twice(42));
		Sys.println(Ops.local("kept", "kept"));
	}
}
