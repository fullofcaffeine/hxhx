/** Uses the selected standard-library provider to observe inherited message and raw value. */
@:access(haxe.ValueException)
class Main {
	static function main():Void {
		final exception = new haxe.ValueException("wrapped");
		Sys.println(exception.message);
		Sys.println(exception.unwrap());
	}
}
