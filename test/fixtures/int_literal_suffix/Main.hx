/**
	Suffixed integer literals have their suffix's type (haxe_ocaml-st8tx): upstream Haxe 4.3.7
	types `7i32` as Int, `7u32` as UInt and `7i64` as haxe.Int64.
**/
class Main {
	static function same<T>(a:T, b:T):Bool
		return a == b;

	static function main() {
		final small:Int = 7i32;
		final unsigned:UInt = 7u32;
		final wide:haxe.Int64 = 7i64;
		Sys.println(same(7i32, 7) + " " + same(small, 7) + " " + same(unsigned, (7 : UInt)) + " " + (wide == haxe.Int64.make(0, 7)));
	}
}
