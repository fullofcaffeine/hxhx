import js.Syntax;
import js.Syntax.typeof as kind;
import js.Syntax.code as raw;
import js.Syntax.delete as erase;

/** A method with the same name is an ordinary user function. */
class UserSyntax {
	public static function code(value:String):String
		return "ordinary:" + value;

	public static function typeof(value:Int):String
		return "ordinary:" + value;

	public static function delete(value:Int, key:String):Bool
		return value == 7 && key == "ordinary";
}

/** Observe native typeof and deletion through their real APIs, preserving special lookup behavior and effects. */
class Main {
	static var effects:Int = 0;
	static var order:String = "";
	static var record:{value:Int} = {value: 7};

	static function receiver():{value:Int} {
		order += "receiver;";
		return record;
	}

	static function key():String {
		order += "key;";
		return "value";
	}

	static function next():Int {
		effects++;
		return 7;
	}

	static function main():Void {
		if (Syntax.typeof(null) != "object")
			throw "null type";
		if (kind(7) != "number")
			throw "alias type";
		if (Syntax.typeof(true) != "boolean")
			throw "boolean type";
		if (Syntax.typeof("text") != "string")
			throw "string type";
		if (Syntax.typeof({value: 7}) != "object")
			throw "object type";
		if (Syntax.typeof(function():Void {}) != "function")
			throw "function type";
		if (Syntax.typeof(next() + 1) != "number" || effects != 1)
			throw "single evaluation";
		// JavaScript values without a Haxe literal enter only through this target API boundary.
		if (Syntax.typeof(raw("undefined")) != "undefined")
			throw "undefined value";
		if (Syntax.typeof(Syntax.code("missing_typeof_fixture_value")) != "undefined")
			throw "undefined name";
		if (UserSyntax.code("value") != "ordinary:value")
			throw "user code method rewritten";
		if (UserSyntax.typeof(7) != "ordinary:7")
			throw "user method rewritten";
		if (!erase(receiver(), key()) || order != "receiver;key;" || record.value != null)
			throw "delete order, effects, or result";
		if (!Syntax.delete(record, "absent"))
			throw "delete missing property";
		final values = [10, 20];
		if (!Syntax.delete(values, 0) || values.length != 2 || values[0] != null || values[1] != 20)
			throw "delete numeric key must preserve array length and other slots";
		if (!UserSyntax.delete(7, "ordinary"))
			throw "user delete method rewritten";
	}
}
