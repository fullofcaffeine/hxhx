import haxe.extern.EitherType;

typedef Position = {line:Int, character:Int};
typedef Range = {start:Position, end:Position};
typedef RangePlaceholder = {range:Range, placeholder:String};
typedef DefaultBehaviour = {defaultBehavior:Bool};
typedef PrepareRenameResult = EitherType<Range, EitherType<RangePlaceholder, DefaultBehaviour>>;

/**
	A value converts into an abstract through a chain of nested `from` conversions, as in Haxe
	4.3.7 (haxe_ocaml-c6wur): `EitherType<Range, EitherType<RangePlaceholder, DefaultBehaviour>>`
	accepts each of the three structures.
**/
class Main {
	public static function test2(r:PrepareRenameResult):String
		return "ok";

	static function main() {
		final pos:Position = {line: 1, character: 10};
		final range:Range = {start: pos, end: pos};
		Sys.println(test2({range: range, placeholder: "Haxe"}) + " " + test2(range) + " " + test2({defaultBehavior: true}));
	}
}
