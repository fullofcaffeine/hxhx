/** Nullable String values preserve text, null, and effects at a Dynamic API boundary. */
class Main {
	static var calls:Int = 0;

	static function value(present:Bool):Null<String> {
		calls++;
		return present ? "finish" : null;
	}

	static function main():Void {
		Sys.println(value(true));
		Sys.println(value(false));
		final stored:Null<String> = value(true);
		Sys.println(stored);
		final empty:Null<String> = value(false);
		Sys.println(empty);
		Sys.println({
			final result = value(true);
			result;
		});
		Sys.println({
			final result = value(false);
			result;
		});
		Sys.println(calls);
	}
}
