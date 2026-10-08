/** Returned local aliases preserve the callback's identity and Boolean conversions. */
class Main {
	/** Dynamic models an authored generic callback; reject a lost Boolean tag immediately. */
	static function echo(value:Dynamic):Dynamic {
		if (!Std.isOfType(value, Bool))
			throw "Boolean callback argument lost its type";
		return value;
	}

	static function fromParameter(callback:Dynamic->Dynamic):Bool->Bool {
		final alias:Bool->Bool = callback;
		Sys.println(alias(true));
		return alias;
	}

	static function fromStatic():Bool->Bool {
		final alias:Bool->Bool = echo;
		Sys.println(alias(true));
		return alias;
	}

	static function original():Dynamic->Dynamic {
		return echo;
	}

	static function fromCall():Bool->Bool {
		final alias:Bool->Bool = original();
		Sys.println(alias(true));
		return alias;
	}

	static function main() {
		final callback:Dynamic->Dynamic = echo;
		final parameter = fromParameter(callback);
		Sys.println(parameter(false));
		Sys.println(parameter == callback);
		final declared = fromStatic();
		Sys.println(declared(false));
		Sys.println(declared == callback);
		final called = fromCall();
		Sys.println(called(false));
		Sys.println(called == callback);
	}
}
