/**
	An Int literal stored into a Float slot (`[1, 2]` as `Array<Float>`, or
	`box.v = 3` for a `Float` field) is promoted natively since PR #123, and a
	whole-number Float prints as upstream does since the November 2026
	consolidation (haxe_ocaml-vzr17), so `++` on it must match upstream.
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
