/** A same-spelled user class must not become the standard-library Map specialization. */
class IntMap {
	public function new() {}
}

/** Distinguish Map key families, null, unrelated values, and evaluation count. */
class Main {
	static var evaluations:Int = 0;

	static function make():Map<Int, String> {
		evaluations++;
		return [1 => "one"];
	}

	static function main():Void {
		final ints = [1 => "one"];
		final strings = ["one" => 1];
		Sys.println(ints is haxe.ds.StringMap);
		Sys.println(strings is haxe.ds.IntMap);
		final missing:Map<Int, String> = null;
		Sys.println(missing is haxe.ds.IntMap);
		final ordinary:Array<Int> = [1, 2];
		Sys.println(ordinary is haxe.ds.IntMap);
		Sys.println(new IntMap() is haxe.ds.IntMap);
		Sys.println(make() is haxe.ds.IntMap);
		Sys.println(evaluations);
	}
}
