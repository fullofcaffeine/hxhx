/**
	A `@:coreType` abstract's header conversions are casts, as in Haxe 4.3.7:
	`Tools.release(a)` for `release(handle:Handle)` with `@:coreType abstract Async to Handle`.
	eval's luv handles (`eval.luv.Async`, `eval.luv.Timer`, ...) declare `to Handle` this way.
	The operations live in their own class, declared before `Main`, so that calls from `main`
	cannot supply the evidence.
**/
@:coreType abstract Handle {}
@:coreType abstract Async to Handle {}

class Tools {
	public static function release(handle:Handle):Int
		return 1;

	public static function keep(handle:Handle):Handle
		return handle;
}

class Ops {
	public static function free(async:Async, count)
		return Tools.release(async) + count;

	public static function held(async:Async)
		return Tools.keep(async);
}

class Main {
	static function main() {
		Sys.println("typed");
	}
}
