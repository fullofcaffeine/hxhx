/**
	A module-level `macro function` is a macro, as in Haxe 4.3.7 (haxe_ocaml-qaauj): its call is typed
	by its expansion, so `same("value", foo())` passes `foo()` as a String. A plain module-level
	function stays an ordinary function.
**/
macro function foo() {
	return macro "value";
}

function plain():Int
	return 1;

class Main {
	static function same<T>(a:T, b:T):Bool
		return a == b;

	static function main() {
		Sys.println(same("value", foo()) + " " + same(1, plain()));
	}
}
