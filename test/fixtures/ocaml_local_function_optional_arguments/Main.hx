/**
	Local functions with optional and defaulted parameters, compared with
	upstream Haxe 4.3.7 `--run`. Each one is called with and without the
	argument. Omitted arguments arrive as null and select the default.

	The last cases call through nullable function locals (`?g:Int->Int`,
	`Null<Int->Int>`). The typed tree records no checked call for such a callee,
	so the declared local type supplies the parameter list.
**/
class Main {
	static function apply(?g:Int->Int):Int {
		return g == null ? 0 : g(3);
	}

	static function main():Void {
		function pick(?x:Int):Int {
			if (x == null)
				return -1;
			return x;
		}
		Sys.println(pick());
		Sys.println(pick(4));

		function add(a:Int, b:Int = 3):Int {
			return a + b;
		}
		Sys.println(add(1));
		Sys.println(add(1, 10));

		function label(?prefix:String, name:String = "x"):String {
			return (prefix == null ? "-" : prefix) + name;
		}
		Sys.println(label());
		Sys.println(label("a"));
		Sys.println(label("a", "b"));

		function scale(x:Float = 1.5, ?by:Float):String {
			return "" + (by == null ? x : x * by);
		}
		Sys.println(scale());
		Sys.println(scale(2.5));
		Sys.println(scale(2.5, 3.0));

		function steps(n:Int, ?step:Int):Int {
			return step == null ? n : n * step;
		}
		Sys.println(steps(5));
		Sys.println(steps(5, 2));

		function tagged(?count:Int, text:String):String {
			return (count == null ? "none" : "" + count) + ":" + text;
		}
		Sys.println(tagged("s"));
		Sys.println(tagged(2, "s"));

		final arrow = (?n:Int) -> n == null ? 0 : n * 2;
		Sys.println(arrow());
		Sys.println(arrow(5));

		Sys.println(apply());
		Sys.println(apply(v -> v + 1));

		function local(h:Null<Int->Int>):Int {
			return h(4);
		}
		Sys.println(local(v -> v * 2));

		final show = (v:Int) -> "v" + v;
		var g:Null<Int->String> = null;
		g = show;
		Sys.println(g(3));

		final nullablePick:Null<(?x:Int) -> Int> = pick;
		Sys.println(nullablePick());
	}
}
