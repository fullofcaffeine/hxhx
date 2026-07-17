import haxe.Int64;

/**
	Repo-owned behavior oracle for the `Int - Int64` operator.

	The cases cover positive and negative right operands, a negative left
	operand, computed operands, and both ends of the signed 64-bit range.
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

	static function computedLeft():Int {
		return 56;
	}

	static function computedRight():Int64 {
		return Int64.add(Int64.ofInt(8), Int64.ofInt(6));
	}

	static function main():Void {
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final minimum = Int64.add(maximum, Int64.ofInt(1));

		emit("left-positive", Int64.toStr(44 - Int64.ofInt(2)));
		emit("right-negative", Int64.toStr(5 - Int64.ofInt(-8)));
		emit("negative-left", Int64.toStr(-5 - Int64.ofInt(8)));
		emit("zero-minus-min", Int64.toStr(0 - minimum));
		emit("negative-one-minus-min", Int64.toStr(-1 - minimum));
		emit("computed", Int64.toStr(computedLeft() - computedRight()));
	}
}
