/** Meta-type values describe runtime categories; ordinary enum values retain their declaration identity. */
class Item {
	public function new() {}
}

enum Choice {
	Empty;
	Value(number:Int);
}

class Main {
	static function main():Void {
		Sys.println("dynamic:" + Std.isOfType(7, Dynamic) + "," + Std.isOfType(null, Dynamic) + "," + Std.isOfType({}, Dynamic));
		Sys.println("class:" + Std.isOfType(Item, Class) + "," + Std.isOfType(new Item(), Class) + "," + Std.isOfType(Choice, Class));
		Sys.println("enum:" + Std.isOfType(Choice, Enum) + "," + Std.isOfType(Empty, Enum) + "," + Std.isOfType(Item, Enum));
		Sys.println("meta:" + Std.isOfType(Dynamic, Class) + "," + Std.isOfType(Class, Class) + "," + Std.isOfType(Enum, Class));
		Sys.println("primitive:" + Std.isOfType(Int, Class) + "," + Std.isOfType(Float, Class) + "," + Std.isOfType(Bool, Enum));
		Sys.println("instances:" + Std.isOfType(Empty, Choice) + "," + Std.isOfType(Value(2), Choice) + "," + Std.isOfType({}, Choice));
		Sys.println("operands:" + (7 is Dynamic) + "," + (Item is Class) + "," + (Choice is Enum) + "," + (Empty is Choice));
		var beforeDynamic = Dynamic;
		var replacement:Dynamic = {};
		untyped Dynamic = replacement;
		Sys.println("replace-dynamic:"
			+ ((cast Dynamic : Dynamic) == replacement)
			+ ","
			+ ((cast beforeDynamic : Dynamic) == (cast Dynamic : Dynamic)));
		untyped Dynamic = beforeDynamic;
		var beforeClass = Class;
		untyped Class = replacement;
		Sys.println("replace-class:"
			+ ((cast Class : Dynamic) == replacement)
			+ ","
			+ ((cast beforeClass : Dynamic) == (cast Class : Dynamic)));
		untyped Class = beforeClass;
		var beforeEnum = Enum;
		untyped Enum = replacement;
		Sys.println("replace-enum:" + ((cast Enum : Dynamic) == replacement) + "," + ((cast beforeEnum : Dynamic) == (cast Enum : Dynamic)));
		untyped Enum = beforeEnum;
		Sys.println("restored:" + (Dynamic == beforeDynamic) + "," + (Class == beforeClass) + "," + (Enum == beforeEnum));
	}
}
