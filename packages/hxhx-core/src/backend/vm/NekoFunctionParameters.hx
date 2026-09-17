package backend.vm;

/**
	Selects optional-argument adaptation and reserves its generated array name.

	Neko functions have fixed arity. Optional or defaulted Haxe parameters need
	values from the variable-argument adapter before the function body executes.
	The generated array must not share a name with any projected parameter,
	because binding the first parameter could otherwise destroy later inputs.
	Static helpers support the current compiler bootstrap discovery route.
**/
class NekoFunctionParameters {
	public static function needsAdapter(arguments:Array<HxFunctionArg>):Bool {
		for (argument in arguments) {
			if (HxFunctionArg.getIsOptional(argument))
				return true;
			switch (HxFunctionArg.getDefaultValue(argument)) {
				case Default(_):
					return true;
				case NoDefault:
			}
		}
		return false;
	}

	/** Accepts the final target parameter names, after identifier normalization. */
	public static function arrayName(parameterNames:Array<String>):String {
		final base = "__hxhx_args";
		var result = base;
		var suffix = 0;
		while (parameterNames.indexOf(result) >= 0)
			result = base + "_" + ++suffix;
		return result;
	}
}
