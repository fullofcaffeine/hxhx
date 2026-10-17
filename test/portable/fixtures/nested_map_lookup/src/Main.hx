/** Nested lookup receivers preserve mutation, identity, nulls, and evaluation order. */
class Main {
	static var effects:String = "";

	static function receiver(value:Map<String, Map<Int, String>>):Map<String, Map<Int, String>> {
		effects += "R";
		return value;
	}

	static function outerKey(value:String):String {
		effects += "O";
		return value;
	}

	static function innerKey():Int {
		effects += "K";
		return 3;
	}

	static function innerValue():String {
		effects += "V";
		return "finish";
	}

	static function require(value:Bool, name:String):Void {
		if (!value)
			throw "Nested Map failed: " + name;
	}

	static function main():Void {
		final nested:Map<String, Map<Int, String>> = ["outer" => [3 => "start"]];
		nested.get("outer").set(3, "finish");
		Sys.println(nested.get("outer").get(3));
		final original:Map<Int, String> = [3 => "start"];
		final strings:Map<String, Map<Int, String>> = ["outer" => original];
		receiver(strings).get(outerKey("outer")).set(innerKey(), innerValue());
		require(effects == "ROKV", "successful effects");
		require(strings.get("outer") == original && original.get(3) == "finish", "string lookup identity");
		final ints:Map<Int, Map<Int, String>> = [7 => original];
		ints.get(7).set(3, "integer");
		require(original.get(3) == "integer", "integer lookup mutation");
		final key = new Key();
		final objects:Map<Key, Map<Int, String>> = [key => original];
		objects.get(key).set(3, "object");
		require(original.get(3) == "object", "object lookup mutation");
		final stringInner:Map<String, String> = ["value" => "start"];
		final stringNested:Map<Int, Map<String, String>> = [1 => stringInner];
		stringNested.get(1).set("value", "string inner");
		require(stringInner.get("value") == "string inner", "string inner carrier");
		final objectInner:Map<Key, String> = [key => "start"];
		final objectNested:Map<Int, Map<Key, String>> = [1 => objectInner];
		objectNested.get(1).set(key, "object inner");
		require(objectInner.get(key) == "object inner", "object inner carrier");
		effects = "";
		var caught = false;
		// The deliberate exception stays at this test boundary; its untyped value does not escape.
		try {
			receiver(strings).get(outerKey("missing")).set(innerKey(), innerValue());
		} catch (_:Dynamic) {
			caught = true;
		}
		require(caught && effects == "RO", "null throws before set arguments");
		Sys.println("nested Map contracts: OK");
	}
}

/** Concrete identity key used by outer and inner maps. */
class Key {
	public function new() {}
}
