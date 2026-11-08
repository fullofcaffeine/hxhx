/**
	Recursive local functions, compared with upstream Haxe 4.3.7 `--run`.

	A named local function is in scope inside its own body, so it can call itself
	directly or from a nested closure. Two local functions can call each other
	only through a variable declared before both (upstream rejects a call to a
	later named function). A `var f = function ...` value does not see its own
	name, so an inner `f` still means the earlier binding.
**/
class Main {
	static function main():Void {
		function fact(n:Int):Int {
			if (n <= 1)
				return 1;
			return n * fact(n - 1);
		}
		Sys.println(fact(5));

		function sum(n:Int):Int
			return n <= 0 ? 0 : n + sum(n - 1);
		Sys.println(sum(4));

		function repeat(text:String, count:Int):String
			return count <= 0 ? "" : text + repeat(text, count - 1);
		Sys.println(repeat("ab", 3));

		var visited = 0;
		function visit(depth:Int):Void {
			visited++;
			if (depth > 0)
				visit(depth - 1);
		}
		visit(3);
		Sys.println(visited);

		function countDown(n:Int):Int {
			final step = function():Int return countDown(n - 1);
			return n <= 0 ? 0 : 1 + step();
		}
		Sys.println(countDown(3));

		function outer(n:Int):Int {
			function inner(k:Int):Int
				return k <= 0 ? n : inner(k - 1) + 1;
			return inner(n);
		}
		Sys.println(outer(2));

		var isOdd:Int->Bool = null;
		function isEven(n:Int):Bool
			return n == 0 ? true : isOdd(n - 1);
		isOdd = function(n:Int):Bool return n == 0 ? false : isEven(n - 1);
		Sys.println(isEven(4));
		Sys.println(isOdd(7));

		var later:Int->Int = null;
		later = function(n:Int):Int return n <= 0 ? 0 : n + later(n - 1);
		Sys.println(later(3));

		function twice(n:Int):Int
			return n * 2;
		Sys.println(twice(21));

		final shadow = function(n:Int):Int return n + 1;
		final shadow = function(n:Int):Int return shadow(n) * 10;
		Sys.println(shadow(1));
	}
}
