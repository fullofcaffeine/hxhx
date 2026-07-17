import haxe.Int64;

/**
	Repo-owned behavior oracle for the commutative `Int64 + Int` operator.

	The cases cover both operand orders, signed deltas, computed operands, and
	wrapping at both ends of the signed 64-bit range.
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
		return Int64.add(Int64.ofInt(20), Int64.ofInt(8));
	}

	static function computedDelta():Int {
		return 14;
	}

	static function main():Void {
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final minimum = Int64.add(maximum, Int64.ofInt(1));
		final minusOne = -1;

		emit("right-positive", Int64.toStr(Int64.ofInt(40) + 2));
		emit("left-positive", Int64.toStr(2 + Int64.ofInt(40)));
		emit("right-negative", Int64.toStr(Int64.ofInt(5) + -8));
		emit("left-negative", Int64.toStr(-8 + Int64.ofInt(5)));
		emit("max-plus-one", Int64.toStr(maximum + 1));
		emit("one-plus-max", Int64.toStr(1 + maximum));
		emit("min-minus-one", Int64.toStr(minimum + minusOne));
		emit("computed-right", Int64.toStr(computedBase() + computedDelta()));
		emit("computed-left", Int64.toStr(computedDelta() + computedBase()));
	}
}
