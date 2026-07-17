import haxe.Int64;

/**
	Repo-owned behavior oracle for the Int64 bitwise-complement operator.

	The cases cover ordinary values, signed boundaries, a value that crosses the
	32-bit word boundary, computed input, and the complement involution.
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

	static function computedValue():Int64 {
		return Int64.add(Int64.ofInt(40), Int64.ofInt(2));
	}

	static function main():Void {
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final minimum = Int64.add(maximum, Int64.ofInt(1));
		final lowerWordBoundary = Int64.make(0, -0x7FFFFFFF - 1);

		emit("zero", Int64.toStr(~Int64.ofInt(0)));
		emit("one", Int64.toStr(~Int64.ofInt(1)));
		emit("negative-one", Int64.toStr(~Int64.ofInt(-1)));
		emit("positive", Int64.toStr(~Int64.ofInt(42)));
		emit("negative", Int64.toStr(~Int64.ofInt(-42)));
		emit("computed", Int64.toStr(~computedValue()));
		emit("maximum", Int64.toStr(~maximum));
		emit("minimum", Int64.toStr(~minimum));
		emit("lower-word-boundary", Int64.toStr(~lowerWordBoundary));
		emit("involution-positive", Int64.toStr(~(~Int64.ofInt(42))));
		emit("involution-minimum", Int64.toStr(~(~minimum)));
		emit("involution-maximum", Int64.toStr(~(~maximum)));
	}
}
