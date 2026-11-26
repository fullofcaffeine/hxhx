/**
	A macro function's parameter without a written type is an Expr in the macro context, so every
	call may pass any expression (follow-up to haxe_ocaml-q3mio). Upstream unit
	HelperMacros.typeString(e) is called with values of several types in one test.
**/
class Main {
	static function main() {
		final value:Null<Int> = 3;
		Sys.println(Macros.show(value) + " " + Macros.show("text") + " " + Macros.pair(value + 1, "x") + " " + Macros.pair("y", 2.5));
		Sys.println(Macros.maybe() + " " + Macros.maybe(1) + " " + Macros.maybe("z"));
	}
}
