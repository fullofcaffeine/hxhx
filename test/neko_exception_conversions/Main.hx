/** The test directly observes compiler exception helpers without changing their declarations. */
@:access(haxe.Exception)
class Main {
	static function main():Void {
		final original = new haxe.Exception("problem");
		final same = haxe.Exception.caught(original);
		Sys.println(same.message);
		Sys.println(same == original);
		final converted = haxe.Exception.caught("primitive");
		Sys.println(converted.message);
		Sys.println(haxe.Exception.thrown(converted) == "primitive");
		Sys.println(haxe.Exception.thrown(original) == original);
	}
}
