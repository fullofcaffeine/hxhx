import haxe.Int64;

/**
	Repo-owned behavior oracle for the `Int % Int64` operator.

	The cases cover remainder signs, zero and computed operands, large Int64
	divisors, modulo by zero, and signed boundary behavior.
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

	static function computedDividend():Int {
		return 86;
	}

	static function computedDivisor():Int64 {
		return Int64.add(Int64.ofInt(8), Int64.ofInt(1));
	}

	static function zeroDivisor():Int64 {
		return Int64.ofInt(0);
	}

	static function emitBasicCases():Void {
		emit("positive-remainder", Int64.toStr(43 % Int64.ofInt(5)));
		emit("negative-dividend", Int64.toStr(-43 % Int64.ofInt(5)));
		emit("negative-divisor", Int64.toStr(43 % Int64.ofInt(-5)));
		emit("both-negative", Int64.toStr(-43 % Int64.ofInt(-5)));
		emit("zero-numerator", Int64.toStr(0 % Int64.ofInt(-7)));
		emit("computed-remainder", Int64.toStr(computedDividend() % computedDivisor()));
	}

	static function emitExceptionCases():Void {
		try {
			emit("modulo-by-zero", Int64.toStr(7 % zeroDivisor()));
		} catch (error:Dynamic) {
			emit("modulo-by-zero", Std.string(error));
		}

		final intMinimum = -0x7FFFFFFF - 1;
		emit("int-min-mod-negative-one", Int64.toStr(intMinimum % Int64.ofInt(-1)));
	}

	static function emitBoundaryCases():Void {
		final intMaximum = 0x7FFFFFFF;
		final intMinimum = -0x7FFFFFFF - 1;
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final minimum = Int64.add(maximum, Int64.ofInt(1));

		emit("int-max-mod-one", Int64.toStr(intMaximum % Int64.ofInt(1)));
		emit("int-min-mod-one", Int64.toStr(intMinimum % Int64.ofInt(1)));
		emit("int-max-mod-int64-max", Int64.toStr(intMaximum % maximum));
		emit("int-min-mod-int64-min", Int64.toStr(intMinimum % minimum));
		emit("int-min-mod-int-min", Int64.toStr(intMinimum % Int64.ofInt(intMinimum)));
	}

	static function main():Void {
		emitBasicCases();
		emitExceptionCases();
		emitBoundaryCases();
	}
}
