import Main.Base;
import Main.Child;

/** Observe ordered operands and abrupt completion using the upstream native runtime. */
class Oracle {
	static var effects:String = "";

	static function value(mode:String):Base {
		effects += "v";
		if (mode == "value")
			throw "value";
		return mode == "null-value" ? null : new Child(7);
	}

	static function target(mode:String):Class<Child> {
		effects += "t";
		if (mode == "target")
			throw "target";
		return mode == "null-target" ? null : Child;
	}

	static function main():Void {
		final mode = Sys.args()[0];
		try {
			final result = Std.downcast(value(mode), target(mode));
			Sys.println(result == null ? "null" : "value=" + result.value);
		} catch (error:String)
			Sys.println("error=" + error);
		Sys.println("effects=" + effects);
	}
}
