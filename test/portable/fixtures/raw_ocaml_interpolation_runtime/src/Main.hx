/** Proves that typed raw-OCaml interpolation keeps normal Haxe runtime-use checks. */
class Main {
	static function makeValues():Array<Int> {
		return [1];
	}

	static function main():Void {
		final values = makeValues();
		final result:Int = cast(untyped __ocaml__("(let _ = {0} in 7)", values[0] = 3));
		Sys.println("result=" + result);
		Sys.println("stored=" + values[0]);
	}
}
