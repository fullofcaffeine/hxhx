/** A parenthesized switch operand can continue with an index before its arms. */
class Main {
	static function choose(values:Array<Int>):String {
		final selected = switch (values) [0]
		{
			case 0:
				"zero";
			case _:
				"other";
		};
		return selected;
	}

	static function main():Void {
		Sys.println(choose([0]));
		Sys.println(choose([2]));
	}
}
