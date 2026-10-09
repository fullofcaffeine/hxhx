import haxe.ds.Map;

using ContextExtensions;

/** The primary signature supplies empty-literal context before later overloads. */
class Api {
	@:overload(function(value:Map<Int, String>):Bool {})
	public static function arrayFirst(value:Array<Int>):Int
		return 1;

	@:overload(function(value:Array<Int>):Int {})
	public static function mapFirst(value:Map<Int, String>):Bool
		return false;
}

/** Empty literals need the selected field, local, return, or parameter contract. */
class Main {
	static var field:Map<Int, String> = [];

	static function returned():Map<Int, String>
		return [];

	static function local():Map<Int, String> {
		final value:Map<Int, String> = [];
		return value;
	}

	static function take(value:Map<Int, String>):Bool
		return value.exists(1);

	static function argument():Bool
		return take([]);

	static function generic<V>():Map<String, V>
		return [];

	static function ordinary():Array<Int>
		return [];

	static function assignedLocal(value:Map<Int, String>):Map<Int, String> {
		value = [];
		return value;
	}

	static function assignedField():Bool {
		field = [];
		return field.exists(1);
	}

	static function assignedElement(values:Array<Map<Int, String>>):Void {
		values[0] = [];
	}

	static function assignedArray(value:Array<Int>):Array<Int> {
		value = [];
		return value;
	}

	static function genericAssignment<V>(value:Map<String, V>):Map<String, V> {
		value = [];
		return value;
	}

	static function conditionalMap(flag:Bool):Map<Int, String>
		return flag ? [] : [];

	static function conditionalArray(flag:Bool):Array<Int>
		return flag ? [] : [1];

	static function overloadArray():Int
		return Api.arrayFirst([]);

	static function overloadMap():Bool
		return Api.mapFirst([]);

	static function genericTake<V>(value:Map<String, V>, witness:V):Bool
		return value.exists("one");

	static function genericArgument():Bool
		return genericTake([], "witness");

	static function extensionArgument():Bool
		return "witness".takeContext([]);

	static function genericExtensionArgument<V>(witness:V):Bool
		return witness.takeGenericContext([]);

	static function main():Void {
		Sys.println(field.exists(1));
		Sys.println(returned().exists(1));
		Sys.println(local().exists(1));
		Sys.println(argument());
		final values:Map<String, String> = generic();
		Sys.println(values.exists("one"));
		Sys.println(ordinary().length);
		Sys.println(genericArgument());
		Sys.println(extensionArgument());
		Sys.println(genericExtensionArgument("witness"));
		Sys.println(conditionalMap(true).exists(1));
		Sys.println(conditionalMap(false).exists(1));
		Sys.println(conditionalArray(true).length);
		Sys.println(conditionalArray(false).length);
		Sys.println(assignedLocal([1 => "old"]).exists(1));
		field.set(1, "old");
		Sys.println(assignedField());
		final buckets = [[1 => "old"]];
		assignedElement(buckets);
		Sys.println(buckets[0].exists(1));
		Sys.println(assignedArray([1]).length);
		Sys.println(genericAssignment(["one" => "old"]).exists("one"));
	}
}
