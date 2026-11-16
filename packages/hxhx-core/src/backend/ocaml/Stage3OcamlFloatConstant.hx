package backend.ocaml;

/**
	Render a Float switch constant as an exact OCaml float expression.

	Why
	- A pattern such as `case 0.1:` must compare against exactly the double
	  that upstream Haxe reads from the source. Printing the value with
	  `Std.string` depends on the host and can round. Rebuilding the double
	  from its IEEE-754 bits is exact on every host.

	What
	- `render("1.5")` returns `(Int64.float_of_bits 0x3FF8000000000000L)`.
**/
class Stage3OcamlFloatConstant {
	public static function render(text:String):String {
		return "(Int64.float_of_bits 0x" + HxFloatPatternBits.of(HxFloatPatternText.value(text)) + "L)";
	}
}
