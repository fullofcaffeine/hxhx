import haxe.Int32;

/**
	`++`/`--` on `Int32` values, and text for `UInt` values above `0x7FFFFFFF`.

	`Int32`: prefix and postfix forms on a local, a parameter, and a field, in
	statement and value positions, including the wrap at 2^31.

	`UInt`: `Std.string`, String concatenation, comparisons, division,
	remainder, wrap-around, and `++`/`--` on locals, an instance field, and an
	array element. Where the static type is `UInt`, upstream prints the
	unsigned value. `Array<UInt>.join` and `Std.string(array)` see the erased
	Int and print "-1" on upstream too, and so does a `UInt` passed directly
	to `Sys.println(v:Dynamic)`. Each value is printed in its own statement, so
	the output does not depend on String concatenation operand order (Bead
	haxe_ocaml-b544p).
**/
class Holder {
	public var count:Int32 = 1;
	public var mask:UInt = 0xFFFFFFFF;

	public function new() {}
}

class Main {
	static function bumped(value:Int32):Int32 {
		value++;
		return value;
	}

	static function main():Void {
		var x:Int32 = 5;
		x++;
		Sys.println("int32 local: " + Std.string(x));
		final before = x--;
		Sys.println("int32 postfix: " + Std.string(before));
		Sys.println("int32 after: " + Std.string(x));
		final pre = ++x;
		Sys.println("int32 prefix: " + Std.string(pre));
		var top:Int32 = 0x7FFFFFFF;
		top++;
		Sys.println("int32 wrap: " + Std.string(top));
		Sys.println("int32 parameter: " + Std.string(bumped(9)));
		final holder = new Holder();
		holder.count++;
		Sys.println("int32 field: " + Std.string(holder.count));

		final big:UInt = 0xFFFFFFFF;
		final mid:UInt = 0x80000000;
		final small:UInt = 7;
		Sys.println(Std.string(big));
		Sys.println("concat " + big);
		Sys.println("concat mid " + mid);
		Sys.println(big);
		Sys.println("field " + holder.mask);
		final values:Array<UInt> = [big, mid, small];
		Sys.println("element " + values[1]);
		Sys.println(Std.string(values[0]));
		Sys.println(values.join(","));
		Sys.println(Std.string(values));
		Sys.println("big > small " + Std.string(big > small));
		Sys.println("mid > small " + Std.string(mid > small));
		Sys.println("small < mid " + Std.string(small < mid));
		Sys.println("big >= mid " + Std.string(big >= mid));
		Sys.println("division " + Std.string(big / 2));
		Sys.println("remainder " + Std.string(big % 10));
		final wrapped:UInt = big + 1;
		Sys.println("wrap " + wrapped);
		var counter:UInt = 0;
		counter--;
		Sys.println("decrement " + counter);
		counter++;
		Sys.println("increment " + counter);
		values[2]--;
		Sys.println("element decrement " + values[2]);
		final nothing:Null<UInt> = null;
		Sys.println("null " + nothing);
		final some:Null<UInt> = big;
		Sys.println("nullable " + some);
	}
}
