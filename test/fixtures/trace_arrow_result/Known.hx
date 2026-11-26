/**
	Arrow bodies that are traces, with a known callback type, so the frozen Stage3 backend can build
	them too (haxe_ocaml-n4s2a). Each trace reports the line of its arrow body.
**/
class Known {
	static function each(items:Array<Int>, f:Int->Void)
		for (item in items)
			f(item);

	static function main() {
		each([1, 2], value -> trace(value));
		each([3], // The arrow body is on the next line.
			value -> trace(value));
		final known:Int->Void = value -> trace(value + 1);
		known(9);
	}
}
