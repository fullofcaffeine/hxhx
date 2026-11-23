/**
	Haxe 4.3.7 compares invariant type arguments with `type_eq`, which follows `Null`, so an
	`Array<Null<Int>>` is passed where an `Array<Int>` is expected. A null slot read through the
	`Int` view is `null` under `--interp`; static targets (reflaxe.ocaml, haxe_ocaml-9cqxj) give 0.
**/
class Values {
	public static function count(values:Array<Int>):Int
		return values.length;

	public static function second(values:Array<Int>):Int
		return values[1];
}

/** The observed operations take simple inputs; `Values` holds the `Array<Int>` parameters. **/
class Ops {
	public static function nested(first:Null<Int>, second:Null<Int>) {
		final values:Array<Null<Int>> = [first, second];
		return Values.count(values);
	}

	public static function slot(first:Null<Int>, second:Null<Int>) {
		final values:Array<Null<Int>> = [first, second];
		return Values.second(values);
	}
}

class Main {
	static function main() {
		Sys.println(Ops.nested(4, null));
		Sys.println(Ops.slot(4, 5));
		Sys.println(Ops.slot(4, null));
	}
}
