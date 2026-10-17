enum PairValue {
	Pair(left:Int, right:Int);
	Mixed(flag:Bool, text:String);
}

/** Alternative captures must live in separate C# lexical scopes. */
class Main {
	static function select(value:PairValue):String {
		return switch value {
			case Pair(item, 2) | Pair(1, item) if (item == 2): "selected";
			case _: "missed";
		};
	}

	static function main():Void {
		Sys.println(select(Pair(1, 2)));
		Sys.println(select(Pair(3, 2)));
		Sys.println(mixed(Mixed(true, "x")));
		Sys.println(mixed(Mixed(false, "x")));
		Sys.println(mixed(Mixed(true, "y")));
	}

	/** Primitive patterns compare boxed enum payloads by value, including strings and Booleans. */
	static function mixed(value:PairValue):String {
		return switch value {
			case Mixed(true, "x") if (true): "matched";
			case _: "unmatched";
		};
	}
}
