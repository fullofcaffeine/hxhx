/**
	Known failing until PR #123 (Bead haxe_ocaml-ljotn) lands.

	An Int literal stored into a Float slot (`[1, 2]` as `Array<Float>`, or
	`box.v = 3` for a `Float` field) is not widened natively: the slot holds
	an Int representation. Reading it back as a Float for `++` then crashes
	the native process (exit 139). `fl[0] = fl[0] + 1.0` crashes the same way
	on main without any `++`, so the bug is in the store, not in the update.
	The test runs this program and requires that it still differs from
	upstream. Once it matches, fold these lines into `stage3_increment_places`.
**/
class Box {
	public var v:Float = 0.5;

	public function new() {}
}

class Main {
	static function main():Void {
		final fl:Array<Float> = [1, 2];
		fl[0]++;
		Sys.println("int literal element: " + fl.join(","));
		final box = new Box();
		box.v = 3;
		box.v++;
		Sys.println("int literal field: " + box.v);
	}
}
