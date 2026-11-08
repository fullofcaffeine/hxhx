/**
	Known failing until whole-number Float printing matches upstream
	(Bead haxe_ocaml-vzr17).

	An Int literal stored into a Float slot (`[1, 2]` as `Array<Float>`, or
	`box.v = 3` for a `Float` field) is promoted natively since PR #123, so
	`++` on it no longer crashes. A whole-number Float still prints as `2.`
	where upstream prints `2`. The test requires exactly that known output.
	Once the output matches upstream, fold these lines into
	`stage3_increment_places`.
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
