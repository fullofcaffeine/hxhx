/**
	A callback and an array argument must preserve their independent shared state.

	The callback runs once and changes its captured counter. The array argument
	keeps its original identity, so the caller's alias observes the appended value.
	This source runs unchanged through upstream Haxe and the native OCaml target.
**/
class Main {
	static function apply(action:() -> Void, values:Array<String>):Void {
		action();
		values.push("kept");
	}

	static function main():Void {
		var calls = 0;
		final values = ["before"];
		final alias = values;
		apply(() -> calls++, values);
		Sys.println('calls=$calls values=' + alias.join(","));
	}
}
