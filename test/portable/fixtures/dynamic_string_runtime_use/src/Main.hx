class Main {
	static final standalone = Std.string((true : Dynamic));

	static function genericText<T>(value:T):String {
		return "generic=" + value;
	}

	static function nestedCatchText(value:Dynamic):String {
		var result = "missing";
		try {
			throw "outer";
		} catch (_:String) {
			try {
				throw "inner";
			} catch (_:String) {
				result = Std.string(value);
			}
		}
		return result;
	}

	static function main():Void {
		Sys.println("standalone=" + standalone);
		final dynamicBool:Dynamic = true;
		Sys.println("std=" + Std.string(dynamicBool));
		Sys.println("concat=" + dynamicBool);

		final record:Dynamic = {answer: 42};
		final fieldName:Dynamic = "answer";
		Sys.println("field=" + Reflect.field(record, fieldName));

		Sys.println("plain=" + Std.string(new PlainValue(1)));
		Sys.println("named=" + Std.string(new NamedValue(2)));
		Sys.println(genericText(3));

		var assigned = "start";
		assigned += dynamicBool;
		Sys.println("assigned=" + assigned);

		final nested = () -> Std.string(dynamicBool);
		Sys.println("nested=" + nested());
		Sys.println("catch=" + nestedCatchText(dynamicBool));
	}
}
