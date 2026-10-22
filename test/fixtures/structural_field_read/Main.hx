/** Exercise the same structural reads before and after field mutation. */
class Main {
	static function record(value:{flag:Bool}):Bool {
		return value.flag;
	}

	static function nested(value:{inner:{count:Int}}):Int {
		return value.inner.count;
	}

	static function dynamicField(value:Dynamic):Dynamic {
		return value.flag;
	}

	static function nullable(value:Null<{flag:Bool}>):Null<Bool> {
		return value?.flag;
	}

	static function main():Void {
		final value = {flag: true};
		Sys.println(record(value));
		value.flag = false;
		Sys.println(record(value));
		Sys.println(dynamicField(value));
		Sys.println(nested({inner: {count: 7}}));
		Sys.println(nullable(null));
		Sys.println(nullable(value));
	}
}
