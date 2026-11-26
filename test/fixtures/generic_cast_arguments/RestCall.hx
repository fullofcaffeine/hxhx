import haxe.Rest;

/** `Rest<T>` converts to `Array<T>` through its `@:to toArray` method. */
class RestCall {
	static function same<T>(a:Array<T>, b:Array<T>):Bool
		return a.length == b.length;

	static function rest(args:Rest<Int>)
		return args;

	static function main() {
		Sys.println(same([0, 1], rest(0, 1)));
	}
}
