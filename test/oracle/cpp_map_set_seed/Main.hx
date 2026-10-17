/** Independently observe operand order, abrupt completion, replacement, and typed value conversion. */
class Main {
	static function main():Void {
		for (mode in ["none", "receiver", "key", "value"]) {
			final target:Map<String, Bool> = ["item" => false];
			var effects = "";
			try {
				MapWrite.strings(() -> {
					effects += "R";
					if (mode == "receiver")
						throw "receiver";
					return target;
				}, () -> {
					effects += "K";
					if (mode == "key")
						throw "key";
					return "item";
				}, () -> {
					effects += "V";
					if (mode == "value")
						throw "value";
					return true;
				});
				Sys.println(mode + ":" + effects + ":" + target.get("item"));
			} catch (error:Dynamic) {
				Sys.println(mode + ":" + effects + ":" + Std.string(error) + ":" + target.get("item"));
			}
		}
		final integers:Map<Int, String> = [];
		MapWrite.integers(() -> integers, () -> 7, () -> "value");
		Sys.println("integer:" + integers.get(7));
		final numbers:Map<String, Float> = [];
		MapWrite.number(() -> numbers, () -> "item", () -> 2);
		Sys.println("number:" + numbers.get("item"));
		for (value in [-2147483647 - 1, -1, 0, 16777217, 2147483647]) {
			MapWrite.number(() -> numbers, () -> "item", () -> value);
			final expected:Float = value;
			if (numbers.get("item") != expected)
				throw "integer widening lost precision";
		}
		Sys.println("widening:5");
		final objects:Map<{id:Int}, {name:String}> = [];
		final key = {id: 1};
		final value = {name: "value"};
		MapWrite.objects(() -> objects, () -> key, () -> value);
		Sys.println("object:" + (objects.get(key) == value) + ":" + (objects.get({id: 1}) == null));
	}
}
