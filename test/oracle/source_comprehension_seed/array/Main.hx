/** Arrow text in a string is an ordinary yielded value, with one result per iteration. */
class Main {
	static function main():Void {
		final result:Array<String> = [for (item in [1, 2]) ("a=>b")];
		Sys.println(result.join(","));
	}
}
