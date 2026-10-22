/** Reflection must return and consume ordinary Haxe arrays at the VM boundary. */
class Holder {
	public static var marker:Int = 1;

	public var value:Int = 5;

	public function new() {}

	public function add(amount:Int):Int
		return value + amount;
}

/** Public reflection and system APIs exchange ordinary Haxe arrays. */
class Main {
	/** A local value named Sys must retain its own callable field. */
	static function shadowedArgs():Int {
		final Sys = {args: function():Int return 42};
		return Sys.args();
	}

	static function main():Void {
		final fields = Reflect.fields({left: 1, right: 2});
		Sys.println(Type.getClass(fields) == Array);
		Sys.println(fields.length);
		Sys.println(fields.indexOf("left") >= 0);
		final savedFields = Reflect.fields;
		Sys.println(Type.getClass(savedFields({only: 1})) == Array);
		final members = Type.getInstanceFields(Holder);
		Sys.println(Type.getClass(members) == Array);
		Sys.println(members.indexOf("add") >= 0);
		final holder = new Holder();
		// Reflect requires heterogeneous arguments; check its result immediately.
		final arguments:Array<Dynamic> = [7];
		final method = Reflect.field(holder, "add");
		if (!Reflect.isFunction(method))
			throw "missing reflected method";
		Sys.println(Reflect.callMethod(holder, method, arguments) == 12);
		Sys.println(Type.getClass(Sys.args()) == Array);
		Sys.println(Sys.args().length);
		members[0] = "poison";
		Sys.println(Type.getInstanceFields(Holder).indexOf("poison") == -1);
		final staticMembers = Type.getClassFields(Holder);
		Sys.println(staticMembers.indexOf("marker") >= 0);
		staticMembers[0] = "poison";
		Sys.println(Type.getClassFields(Holder).indexOf("poison") == -1);
		final commandArguments = Sys.args();
		Sys.println(commandArguments[0]);
		commandArguments[0] = "poison";
		Sys.println(Sys.args()[0]);
		final savedArgs = Sys.args;
		Sys.println(savedArgs()[0]);
		Sys.println(shadowedArgs());
	}
}
