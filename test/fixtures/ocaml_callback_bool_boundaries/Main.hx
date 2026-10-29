/** Callback argument and return conversions preserve Bool tags and the original method identity. */
class Main {
	/** Dynamic is the deliberate erased callback boundary; reject a lost Boolean tag immediately. */
	static function echo(value:Dynamic):Dynamic {
		if (!Std.isOfType(value, Bool))
			throw "Boolean callback argument lost its type";
		return value;
	}

	static function preserve(callback:Bool->Bool):Bool->Bool
		return callback;

	static function dynamicCallback():Dynamic->Dynamic
		return echo;

	static function booleanCallback():Bool->Bool
		return echo;

	static function main():Void {
		final original:Dynamic->Dynamic = echo;
		final passed = preserve(original);
		Sys.println(passed(true));
		Sys.println(passed(false));
		Sys.println(passed == original);
		final fromCall = preserve(dynamicCallback());
		Sys.println(fromCall(true));
		Sys.println(fromCall(false));
		Sys.println(fromCall == original);
		final returned = booleanCallback();
		Sys.println(returned(true));
		Sys.println(returned(false));
		Sys.println(returned == original);
	}
}
