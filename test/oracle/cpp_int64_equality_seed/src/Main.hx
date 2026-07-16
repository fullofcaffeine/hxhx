import haxe.Int64;

/**
	Repo-owned behavior oracle for static `Int64` equality calls.

	The cases keep equality and representation concerns visible separately: equal
	and unequal values, a negative value, the largest signed value, and a value
	produced by arithmetic rather than a literal.
**/
class Main {
	static function emit(label:String, value:Bool):Void {
		final line = label + ":" + value;
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function main():Void {
		final zero = Int64.ofInt(0);
		final one = Int64.ofInt(1);
		final negative = Int64.ofInt(-7);
		final maximum = Int64.make(0x7FFFFFFF, -1);
		final computed = Int64.add(Int64.ofInt(20), Int64.ofInt(22));

		emit("equal", Int64.eq(zero, Int64.ofInt(0)));
		emit("unequal", Int64.eq(zero, one));
		emit("negative", Int64.eq(negative, Int64.neg(Int64.ofInt(7))));
		emit("boundary", Int64.eq(maximum, Int64.make(0x7FFFFFFF, -1)));
		emit("computed", Int64.eq(computed, Int64.ofInt(42)));
		emit("not-equal", Int64.neq(zero, one));
	}
}
