/** Typed record reads preserve null text and evaluate operands in source order. */
class Main {
	static function equal(left:String, right:String):Bool {
		return {name: left}.name == right;
	}

	static function unequal(left:String, right:String):Bool {
		return left != right;
	}

	static function ordered(left:Void->String, right:Void->String):Bool {
		return {name: left()}.name == right();
	}

	static function main():Void {
		Sys.println(equal(null, null));
		Sys.println(equal(null, ""));
		Sys.println(equal("", null));
		Sys.println(equal("", ""));
		Sys.println(equal("hé\x00z", "hé\x00z"));
		Sys.println(unequal("a", "b"));
		Sys.println(unequal(null, null));
		Sys.println(ordered(function():String {
			Sys.print("left:");
			return "same";
		}, function():String {
			Sys.print("right:");
			return "same";
		}));
	}
}
