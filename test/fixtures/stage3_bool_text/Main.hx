class Base {
	public function new() {}
}

class Child extends Base {
	public function new() {
		super();
	}
}

class Main {
	static var flag:Bool = true;
	static var blockFlag:Bool = {
		final ready = 1;
		ready > 0;
	};

	static function yes():Bool {
		return true;
	}

	static function maybeFlag(on:Bool):Null<Bool> {
		return on ? true : null;
	}

	static function optional(?value:Bool):String {
		return value == null ? "omitted" : (value ? "on" : "off");
	}

	static function echo(?value:Bool):String {
		return "echo " + value;
	}

	static function main() {
		final t = true;
		final f = false;
		final one = 1;
		final zero = 0;
		// Concatenation.
		Sys.println("literal " + true + " " + false);
		Sys.println("local " + t + " " + f);
		Sys.println("compare " + (one > zero) + " " + (one == zero));
		Sys.println("call " + yes());
		Sys.println("static " + flag + " " + blockFlag);
		final value:Base = new Child();
		Sys.println("is " + (value is Child) + " " + Std.isOfType(value, Child));
		Sys.println("int " + one + " " + zero);
		// Join and array text.
		final bools = [true, false, t];
		Sys.println(bools.join(","));
		Sys.println(Std.string(bools) + " " + bools.toString());
		// Null<Bool> locals.
		var maybe:Null<Bool> = true;
		Sys.println("nullable " + maybe + " " + Std.string(maybe));
		maybe = false;
		Sys.println("nullable " + maybe);
		maybe = null;
		Sys.println("nullable " + maybe + " " + (maybe == null));
		var set:Null<Bool> = true;
		if (set)
			Sys.println("condition true");
		// Optional Bool parameters.
		Sys.println(optional() + " " + optional(true) + " " + optional(false));
		Sys.println(echo() + " " + echo(true) + " " + echo(false));
		// Map values.
		final map:Map<String, Bool> = ["a" => true, "b" => false];
		Sys.println("map " + map.get("a") + " " + map["b"]);
		// Anonymous objects and Dynamic.
		final record = {ok: true};
		Sys.println(Std.string(record) + " " + record.ok);
		final dynamicValue:Dynamic = false;
		Sys.println("dynamic " + dynamicValue + " " + Std.string(dynamicValue));
		final mixed:Array<Dynamic> = [true, 1, false];
		Sys.println(Std.string(mixed));
		// String building.
		final buffer = new StringBuf();
		buffer.add(true);
		buffer.add(" ");
		buffer.add(f);
		Sys.println(buffer.toString());
		Sys.println('interpolated ${t} ${one > zero}');
		// Nullable results, nullable arrays, and conditional operands.
		Sys.println("result " + maybeFlag(true) + " " + maybeFlag(false));
		final optionalFlags:Array<Null<Bool>> = [true, null, false];
		Sys.println(optionalFlags.join("|"));
		Sys.println("ternary " + (one > zero ? true : false));
	}
}
