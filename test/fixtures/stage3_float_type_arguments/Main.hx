/**
	Int values that meet a Float destination must be promoted to Float, also
	when the destination is a type parameter instantiated with Float.
	Each Float result is printed with a fractional part, so the output does
	not depend on how whole-number Floats are formatted.
**/
interface Box<T> {
	function get():T;
	function put(value:T):Void;
}

class FloatCell implements Box<Float> {
	var value = 0.5;

	public function new() {}

	public function get():Float
		return value;

	public function put(value:Float):Void
		this.value = value;
}

class IntCell implements Box<Int> {
	var value = 0;

	public function new() {}

	public function get():Int
		return value;

	public function put(value:Int):Void
		this.value = value;
}

class Cell<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;

	public function get():T
		return value;

	public function put(value:T):Void
		this.value = value;
}

class Other {
	public var i:Int = 4;

	public function new() {}
}

class Holder {
	public var f:Float = 0.5;

	public function new() {}

	public function setLength(values:Array<Int>):Void
		f = values.length;
}

class Main {
	static function firstAsFloat(values:Array<Int>):Float
		return values[0];

	static function fieldAsFloat(other:Other):Float
		return other.i;

	static function negatedAsFloat():Float
		return -count();

	static function second<T>(first:T, next:T):T
		return next;

	static function half(x:Float):Float
		return x / 2;

	static function count():Int
		return 3;

	static function asFloat(box:Box<Int>):Float
		return box.get();

	static function main() {
		// A generic interface instantiated with Float.
		final floats:Box<Float> = new FloatCell();
		floats.put(2);
		Sys.println("interface put: " + Std.string(floats.get() + 0.25));
		final ints:Box<Int> = new IntCell();
		ints.put(3);
		floats.put(ints.get());
		Sys.println("interface put of Int result: " + Std.string(floats.get() + 0.25));

		// An Int result read where Float is expected.
		var f:Float = ints.get();
		Sys.println("Float local from Int result: " + Std.string(f + 0.5));
		f = count();
		Sys.println("Float local assignment: " + Std.string(f + 0.5));
		Sys.println("Float argument from Int result: " + Std.string(half(ints.get())));
		Sys.println("Float return of Int result: " + Std.string(asFloat(ints) + 0.5));

		// A generic class instantiated with Float.
		final cell = new Cell<Float>(1);
		Sys.println("constructor: " + Std.string(cell.get() + 0.5));
		cell.put(2);
		Sys.println("method: " + Std.string(cell.get() * 1.25));
		final n = 5;
		cell.put(n + 2);
		Sys.println("Int expression: " + Std.string(cell.get() + 0.5));
		cell.value = 4;
		Sys.println("field of type T: " + Std.string(cell.get() + 0.5));

		// Int and Dynamic type arguments keep the Int value.
		final intCell = new Cell<Int>(7);
		intCell.put(9);
		Sys.println("Cell<Int>: " + (intCell.get() + 1));
		final dynamicCell = new Cell<Dynamic>(3);
		dynamicCell.put(4);
		Sys.println("Cell<Dynamic>: " + dynamicCell.get());

		// A nullable Float type argument.
		final maybe = new Cell<Null<Float>>(0.5);
		maybe.put(6);
		final read:Float = maybe.get();
		Sys.println("Cell<Null<Float>>: " + Std.string(read + 0.5));
		maybe.put(null);
		Sys.println("Cell<Null<Float>> null: " + (maybe.get() == null));

		// A generic method whose type parameter is inferred as Float.
		final picked:Float = second(2.5, 2);
		Sys.println("generic method: " + Std.string(picked + 0.25));

		// Array<Float> element writes from Int values.
		final list:Array<Float> = [1, 2.5];
		list.push(n);
		list[1] = ints.get();
		list.insert(0, 8);
		Sys.println("array literal: " + Std.string(list[1] + 0.5));
		Sys.println("array index write: " + Std.string(list[2] + 0.5));
		Sys.println("array push: " + Std.string(list[3] + 0.5));
		Sys.println("array insert: " + Std.string(list[0] + 0.5));

		// Float fields and returns from Int array reads, Int field reads, and negation.
		final holder = new Holder();
		holder.setLength([1, 2, 3, 4]);
		Sys.println("bare field write: " + Std.string(holder.f + 0.25));
		final values = [5, 6];
		holder.f = values[0];
		Sys.println("field from array read: " + Std.string(holder.f + 0.25));
		final other = new Other();
		holder.f = other.i;
		Sys.println("field from Int field: " + Std.string(holder.f + 0.25));
		holder.f = -count();
		Sys.println("field from negation: " + Std.string(holder.f + 0.25));
		Sys.println("return of array read: " + Std.string(firstAsFloat(values) + 0.25));
		Sys.println("return of Int field: " + Std.string(fieldAsFloat(other) + 0.25));
		Sys.println("return of negation: " + Std.string(negatedAsFloat() + 0.25));
		final parsed:Float = Std.parseInt("7");
		Sys.println("Float local from Null<Int>: " + Std.string(parsed + 0.5));
	}
}
