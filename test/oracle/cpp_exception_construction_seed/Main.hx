/** Direct construction must preserve public message, previous-exception, and native identity contracts. */
class Main {
	static function main():Void {
		final previous = new haxe.Exception("first");
		final current = new haxe.Exception("second", previous);
		Sys.println(current.message);
		Sys.println(current.toString());
		Sys.println(current.previous == previous);
		Sys.println(current.native == current);
	}
}
