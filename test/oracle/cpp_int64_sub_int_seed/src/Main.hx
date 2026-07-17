import haxe.Int64;

/**
	Repo-owned behavior oracle for the `Int64 - Int` operator.

	The cases cover positive and negative deltas, a negative left operand,
	computed operands, and wrapping at both ends of the signed 64-bit range.
**/
class Main {
	static function emit(label:String, value:String):Void {
		final line = label + ":" + value;
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function computedBase():Int64 {
		return Int64.add(Int64.ofInt(40), Int64.ofInt(16));
	}

	static function computedDelta():Int {
		return 14;
	}

	static function main():Void {
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final minimum = Int64.add(maximum, Int64.ofInt(1));
		final minusOne = -1;

		emit("right-positive", Int64.toStr(Int64.ofInt(44) - 2));
		emit("right-negative", Int64.toStr(Int64.ofInt(5) - -8));
		emit("negative-base", Int64.toStr(Int64.ofInt(-5) - 8));
		emit("max-minus-negative-one", Int64.toStr(maximum - minusOne));
		emit("min-minus-one", Int64.toStr(minimum - 1));
		emit("computed", Int64.toStr(computedBase() - computedDelta()));
	}
}
