/** Exercises planned String equality through generated and compiled OCaml. */
class Main {
	static var leftCalls = 0;
	static var rightCalls = 0;
	static var order = "";
	static var standaloneLeft = "same";
	static var standaloneRight:Null<String> = "same";
	static final standalone = standaloneLeft == standaloneRight;

	/** Returns a left operand and records its evaluation. */
	static function nextLeft(value:String):String {
		leftCalls++;
		order += "L";
		return value;
	}

	/** Returns a right operand and records its evaluation. */
	static function nextRight(value:String):String {
		rightCalls++;
		order += "R";
		return value;
	}

	static function main():Void {
		final same = "same";
		final equalNullable:Null<String> = "same";
		final different:Null<String> = "different";
		final missingLeft:Null<String> = null;
		final missingRight:Null<String> = null;
		final nested = () -> same != different;

		Sys.println("equal=" + (same == equalNullable));
		Sys.println("notEqual=" + (same != different));
		Sys.println("nullEqual=" + (missingLeft == missingRight));
		Sys.println("nullDifferent=" + (same != missingLeft));
		Sys.println("literalNull=" + (missingLeft == null));
		Sys.println("side=" + (nextLeft("value") == nextRight("value")));
		Sys.println("calls=" + leftCalls + ":" + rightCalls + ":" + order);
		leftCalls = 0;
		rightCalls = 0;
		order = "";
		Sys.println("sideNotEqual=" + (nextLeft("left") != nextRight("right")));
		Sys.println("notEqualCalls=" + leftCalls + ":" + rightCalls + ":" + order);
		Sys.println("nested=" + nested());
		Sys.println("standalone=" + standalone);
	}
}
