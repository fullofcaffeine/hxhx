/**
	Call arguments convert through `@:from`/`@:to` cast methods, as in Haxe 4.3.7 (haxe_ocaml-eonvh).
**/
class Main {
	static function measure(length:Length)
		return length.get();

	static function doSomething(map:haxe.ds.StringMap<Int>)
		return map.get("test");

	static function main() {
		Sys.println(measure("abc"));
		final map = ["test" => 1];
		Sys.println(doSomething(map));
	}
}
