/**
	An original declaration fixture shared by upstream execution and catalog tests.
	The values surround the methods to expose skipped or duplicated declarations.
**/
@:keep
enum abstract Counter<T>(Int) from Int to Int {
	var One = 1;

	@:op(-A)
	public static function reverse<U:Int>(value:Counter<U>):Counter<U> {
		final number:Int = value;
		if (number == 0)
			return 0;
		return -number;
	}

	@:op(++A)
	public inline function advance():Counter<T> {
		this += 1;
		return this;
	}

	@:op(A++)
	public inline function advanceAfter():Counter<T> {
		final previous = this;
		this += 1;
		return previous;
	}

	private function hidden():Int
		return this;

	public function read(?offset:Int = 0):Int
		return hidden() + offset;

	var Three = 3;
}

/** Ordinary enums must keep their constructor surface without abstract operators. */
enum Plain {
	Empty;
	Wrapped(value:Int);
}

/** A neighboring type exposes accidental scanner reads past the closing brace. */
class Neighbor {
	public static function marker():Int
		return 7;
}
