/** Named callbacks retain the input types inferred by addition in their bodies. */
class Main {
	static function left(value)
		return value + 1;

	static function right(value)
		return 1 + value;

	static function pair(left, right)
		return left + right;

	static function alias(value) {
		var local = value;
		return local + 2;
	}

	static function text(value)
		return value + "!";

	static function floating(value)
		return value + 1.5;

	static function dynamicPeer(value, other:Dynamic)
		return value + other;

	static function explicit(value:Dynamic)
		return value + 1;

	static function unused(value)
		return 1;

	static function main() {
		var callback:Int->Int = left;
		Sys.println(callback(4));
		Sys.println(pair(2, 3));
		Sys.println(alias(3));
		Sys.println(text("ok"));
	}
}
