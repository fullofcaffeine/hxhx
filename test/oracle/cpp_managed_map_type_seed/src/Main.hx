/** Check Map family identity, null, unrelated arrays, and once-only operand effects. */
class Main {
	static var missing:Map<Int, String>;
	static var evaluations:Int = 0;

	static function nextKey():Int {
		evaluations = evaluations + 1;
		Sys.println("key");
		return evaluations;
	}

	static function nextValue():String {
		Sys.println("value");
		return "one";
	}

	static function make():Map<Int, String> {
		return [nextKey() => nextValue()];
	}

	/** The literal needs Dynamic storage while its authored value remains Bool. */
	static function contextualValue():Dynamic {
		final values:Map<String, Dynamic> = ["value" => true];
		return values.get("value");
	}

	static function main():Void {
		final ints = [1 => "one"];
		final strings = ["one" => 1];
		Sys.println(ints is haxe.ds.IntMap);
		Sys.println(strings is haxe.ds.StringMap);
		Sys.println(ints is haxe.ds.StringMap);
		Sys.println(ints is haxe.ds.ObjectMap);
		Sys.println(strings is haxe.ds.EnumValueMap);
		Sys.println(missing is haxe.ds.IntMap);
		final array = [1, 2];
		Sys.println(array is haxe.ds.IntMap);
		Sys.println(make() is haxe.ds.IntMap);
		Sys.println(make() is haxe.ds.StringMap);
		Sys.println(evaluations);
		final objects = [
			{id: 7}
			=> "record"
		];
		Sys.println(objects is haxe.ds.ObjectMap);
		Sys.println(objects is haxe.ds.IntMap);
		Sys.println(contextualValue());
	}
}
