/**
	Exercises the nullable integer produced by `Map.get` inside a conditional.

	The nested function matters: the compiler-scale failure occurs inside a
	function declared by another function. The expected result comes from stock
	Haxe 4.3.7 and is checked before the OCaml target is changed.
**/
class Main {
	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function exercise(key:String):Int {
		final counts:Map<String, Int> = [];
		counts.set("present", 2);

		function read():Int {
			final count = counts.exists(key) ? counts.get(key) : 0;
			return count + 1;
		}

		return read();
	}

	static function main():Void {
		emit("present=" + exercise("present"));
		emit("missing=" + exercise("missing"));
	}
}
