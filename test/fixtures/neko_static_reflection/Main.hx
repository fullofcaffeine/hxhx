/** Static reflection shares the authored storage while runtime type metadata stays private. */
class Main {
	static function main():Void {
		Sys.println(Payload.bump(2) == 3);
		final first = Reflect.field(Payload, "bump");
		if (!Reflect.isFunction(first))
			throw "missing static method";
		Sys.println(Reflect.callMethod(null, first, [2]) == 3);
		Sys.println(Reflect.field(Payload, "name") == "owned-name");
		Sys.println(Reflect.field(Payload, "identity") == "owned-identity");
		Sys.println(Reflect.field(Payload, "kind") == "owned-kind");
		Sys.println(Reflect.field(Payload, "prototype") == 17);
		Sys.println(Reflect.field(Payload, "assignable") == 19);
		Sys.println(Reflect.field(Payload, "__hxhx_type_identity") == "owned-internal-looking-name");
		Sys.println(Type.getClassName(Payload) == "Payload");
		final value = new Payload();
		Sys.println(Type.getClass(value) == Payload);
		Sys.println(Std.isOfType(value, Payload));
		Reflect.setField(Payload, "name", "changed");
		Sys.println(Payload.name == "changed");
		Payload.bump = function(value:Int):Int {
			return value + 2;
		};
		final changed = Reflect.field(Payload, "bump");
		if (!Reflect.isFunction(changed))
			throw "missing replacement method";
		Sys.println(Reflect.callMethod(null, changed, [2]) == 4);
		Sys.println(Payload.bump(2) == 4);
		Sys.println(Reflect.callMethod(null, first, [2]) == 3);
	}
}

/** Common user field names must not overwrite compiler metadata on the class object. */
class Payload {
	public static var name = "owned-name";
	public static var identity = "owned-identity";
	public static var kind = "owned-kind";
	public static var prototype = 17;
	public static var assignable = 19;
	public static var __hxhx_type_identity = "owned-internal-looking-name";

	public function new() {}

	public static dynamic function bump(value:Int):Int
		return value + 1;
}
