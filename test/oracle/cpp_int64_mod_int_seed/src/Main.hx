import haxe.Int64;

/**
	Repo-owned behavior oracle for the `Int64 % Int` operator.

	The cases cover remainder signs, zero and computed operands, the public
	`Int64.mod` call, division by zero, and signed 64-bit boundary behavior.
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

	static function computedDividend():Int64 {
		return Int64.add(Int64.ofInt(80), Int64.ofInt(6));
	}

	static function computedDivisor():Int {
		return 9;
	}

	static function zeroDivisor():Int {
		return 0;
	}

	static function emitBasicCases():Void {
		emit("direct-mod", Int64.toStr(Int64.mod(Int64.ofInt(43), Int64.ofInt(5))));
		emit("positive-remainder", Int64.toStr(Int64.ofInt(43) % 5));
		emit("negative-dividend", Int64.toStr(Int64.ofInt(-43) % 5));
		emit("negative-divisor", Int64.toStr(Int64.ofInt(43) % -5));
		emit("both-negative", Int64.toStr(Int64.ofInt(-43) % -5));
	}

	static function emitZeroAndComputedCases():Void {
		emit("zero-numerator", Int64.toStr(Int64.ofInt(0) % -7));
		emit("computed-remainder", Int64.toStr(computedDividend() % computedDivisor()));
		try {
			emit("modulo-by-zero", Int64.toStr(Int64.ofInt(7) % zeroDivisor()));
		} catch (error:Dynamic) {
			emit("modulo-by-zero", Std.string(error));
		}
	}

	static function emitBoundaryCases():Void {
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final minimum = Int64.add(maximum, Int64.ofInt(1));
		final minusOne = -1;
		final intMinimum = -0x7FFFFFFF - 1;

		emit("max-mod-two", Int64.toStr(maximum % 2));
		emit("max-mod-negative-one", Int64.toStr(maximum % minusOne));
		emit("min-mod-three", Int64.toStr(minimum % 3));
		emit("min-mod-negative-one", Int64.toStr(minimum % minusOne));
		emit("max-mod-int-min", Int64.toStr(maximum % intMinimum));
	}

	static function main():Void {
		emitBasicCases();
		emitZeroAndComputedCases();
		emitBoundaryCases();
	}
}
