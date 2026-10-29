/** Observe concrete and Dynamic access to the same authored object. */
class Main {
	static final initialized = {flag: true};

	static function step(name:String, value:Bool):Bool {
		Sys.println(name);
		return value;
	}

	static function fail():Bool {
		throw "stop";
	}

	static function main():Void {
		Sys.println(initialized.flag);
		final object = {flag: true};
		final dynamicObject:Dynamic = object;
		Sys.println(object.flag);
		Sys.println(dynamicObject.flag == 1);
		object.flag = false;
		Sys.println(object.flag);
		dynamicObject.flag = true;
		Sys.println(object.flag);
		final ordered = {first: step("first", true), second: step("second", false)};
		Sys.println(ordered.first);
		Sys.println(ordered.second);
		final first = {};
		final second = {};
		Sys.println(first == second);
		Sys.println(first == first);
		Sys.println(({flag: step("left", true)}) == ({flag: step("right", true)}));
		final nested = {child: {text: "nested", number: 7}};
		Sys.println(nested.child.text);
		Sys.println(nested.child.number);
		try {
			final partial = {first: step("before", true), second: fail(), third: step("after", true)};
			Sys.println(partial.first);
		} catch (message:String) {
			Sys.println(message);
		}
		final nullableValue:Dynamic = null;
		final nullObject = {value: nullableValue};
		Sys.println(nullObject.value == null);
	}
}
