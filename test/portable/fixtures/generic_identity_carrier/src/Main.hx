/**
	Exercises one generic function with two concrete target representations.

	The String call must return OCaml `string`, and the Int call must return
	OCaml `int`. Using both calls prevents the target from incorrectly fixing the
	function to the type of only one caller.
**/
class Main {
	static function identity<T>(value:T):T {
		return value;
	}

	static function main():Void {
		final text = identity("ready");
		final count = identity(41);
		Sys.println("string=" + text.toUpperCase());
		Sys.println("int=" + (count + 1));
	}
}
