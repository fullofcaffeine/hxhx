/**
	Block-bodied local functions that return reference values, compared with
	upstream Haxe 4.3.7 `--run`: an Array, a function value, a class instance
	and an anonymous structure. Identity survives the return.
**/
class Point {
	public var x:Int;

	public function new(x:Int)
		this.x = x;
}

class Main {
	static function main():Void {
		function words(n:Int):Array<String> {
			final out = [];
			for (i in 0...n)
				out.push("w" + i);
			return out;
		}
		Sys.println(words(3).join(","));

		final shared = [1, 2];
		function same(values:Array<Int>):Array<Int> {
			values.push(3);
			return values;
		}
		// Array `==` is not native yet (haxe_ocaml-bqfdl), so the shared
		// mutation shows that the same array came back.
		same(shared).push(4);
		Sys.println(shared.length);

		function adder(k:Int):Int->Int {
			return function(v:Int):Int return v + k;
		}
		Sys.println(adder(2)(5));
		final addThree = adder(3);
		Sys.println(addThree(4));

		function greeter(prefix:String):Void->String {
			return () -> prefix + "!";
		}
		Sys.println(greeter("hi")());

		function point(x:Int):Point {
			return new Point(x);
		}
		final p = point(7);
		Sys.println(p.x);

		function keep(value:Point):Point {
			return value;
		}
		Sys.println(keep(p) == p);

		function pair(a:Int):{first:Int, second:String} {
			return {first: a, second: "s" + a};
		}
		final made = pair(3);
		Sys.println(made.first + made.second);
	}
}
