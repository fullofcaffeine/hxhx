import haxe.Int64;

/**
	Repo-owned behavior oracle for the commutative `Int64 * Int` operator.

	The cases cover both operand orders, signed and zero factors, computed
	operands, the public `Int64.mul` call, and signed 64-bit wraparound.
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
		return Int64.add(Int64.ofInt(3), Int64.ofInt(3));
	}

	static function computedFactor():Int {
		return 7;
	}

	static function emitBasicCases():Void {
		emit("direct-mul", Int64.toStr(Int64.mul(Int64.ofInt(6), Int64.ofInt(7))));
		emit("right-positive", Int64.toStr(Int64.ofInt(21) * 2));
		emit("left-positive", Int64.toStr(2 * Int64.ofInt(21)));
		emit("right-negative", Int64.toStr(Int64.ofInt(7) * -6));
		emit("left-negative", Int64.toStr(-6 * Int64.ofInt(7)));
	}

	static function emitZeroAndComputedCases():Void {
		emit("right-zero", Int64.toStr(Int64.ofInt(-123) * 0));
		emit("left-zero", Int64.toStr(0 * Int64.ofInt(-123)));
		emit("computed-right", Int64.toStr(computedBase() * computedFactor()));
		emit("computed-left", Int64.toStr(computedFactor() * computedBase()));
	}

	static function emitBoundaryCases():Void {
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final minimum = Int64.add(maximum, Int64.ofInt(1));
		final minusOne = -1;

		emit("max-times-two", Int64.toStr(maximum * 2));
		emit("two-times-max", Int64.toStr(2 * maximum));
		emit("min-times-negative-one", Int64.toStr(minimum * minusOne));
		emit("negative-one-times-min", Int64.toStr(minusOne * minimum));
	}

	static function main():Void {
		emitBasicCases();
		emitZeroAndComputedCases();
		emitBoundaryCases();
	}
}
