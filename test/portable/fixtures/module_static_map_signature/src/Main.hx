/** Call one declaration with distinct map types and observe their values afterward. */
class Main {
	static function main():Void {
		final numbers = new haxe.ds.StringMap<Int>();
		numbers.set("first", 41);
		final words = new haxe.ds.StringMap<String>();
		words.set("first", "ready");
		words.set("second", "other");
		final flags = new haxe.ds.StringMap<Bool>();
		flags.set("first", false);
		Sys.println(Left.count(numbers));
		Sys.println(Left.count(words));
		Sys.println(Left.count(flags));
		Sys.println(Left.count(null));
		Sys.println(numbers.get("first") + 1);
		Sys.println(words.get("first").toUpperCase());
		Sys.println(flags.get("first") == false);
	}
}
