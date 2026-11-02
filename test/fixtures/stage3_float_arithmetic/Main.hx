/**
	Binary arithmetic and comparisons whose operands are Float values that the
	emitter cannot see from a literal or a typed local: method results, fields,
	type-parameter results instantiated with Float, Array<Float> elements, and
	`this` inside a Float-backed abstract. Int operands mixed with Float operands
	must be converted to Float, and String + Float must still concatenate.
	Each printed Float has a fractional part, so the output does not depend on
	how whole-number Floats are formatted.
**/
class Cell {
	public var v = 0.5;
	public var side = 3;

	public function new() {}

	public function get():Float
		return v;

	public function put(x:Float):Void
		v = x;

	public function area():Float
		return side * side / 2;

	public function bump(n:Int):Void
		this.v += n;
}

class Point {
	public var x:Int;
	public var y:Int;
	public var w:Float;
	public var h:Float;

	public function new(x:Int, y:Int, w:Float, h:Float) {
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
	}

	public function sum():Int
		return x + y;

	public function explicitSum():Int
		return this.x + this.y;

	public function size():Float
		return w * h;

	public function explicitSize():Float
		return this.w + this.h;

	public function mixed():Float
		return x * w + this.y / 8;
}

class G<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;

	public function get():T
		return value;
}

// Built from a Float value with `from Float`: an abstract constructor that
// assigns `this` has its own open task (haxe_ocaml-bc4pm).
abstract Meters(Float) from Float {
	public function half():Float
		return this / 2;

	public function plus(x:Float):Float
		return this + x;

	public function scaled(n:Int):Float
		return this * n - 0.25;

	public function rest():Float
		return this % 2;

	public function longer(x:Float):Bool
		return this > x;
}

class Main {
	static function pick(up:Bool):Float {
		var y:Float = if (up) 2 else 0.5;
		return y + 0.25;
	}

	static function choose(n:Int):Float {
		final y:Float = switch n {
			case 0: 1;
			case _: 0.75;
		};
		return y + 0.5;
	}

	static function count():Int
		return 3;

	static function main():Void {
		final c = new Cell();
		c.put(1.25);
		// Float method results.
		Sys.println(Std.string(c.get() + 0.5));
		Sys.println(Std.string(c.get() - 0.5));
		Sys.println(Std.string(c.get() * 2.5));
		Sys.println(Std.string(c.get() / 2));
		Sys.println(Std.string(c.get() % 1));
		Sys.println(Std.string(c.get() + c.get()));
		// Float and Int fields.
		Sys.println(Std.string(c.v + 1));
		Sys.println(Std.string(c.side / 2));
		Sys.println(Std.string(c.side + c.v));
		Sys.println(Std.string(c.area()));
		// Type-parameter results instantiated with Float.
		final g = new G(2.5);
		Sys.println(Std.string(g.value / 8));
		Sys.println(Std.string(g.get() + 0.25));
		Sys.println(Std.string(g.value - g.get() + 0.25));
		Sys.println(Std.string(g.value * count() + 0.25));
		// Array<Float> elements.
		final a:Array<Float> = [1.5, 2.25, 0.5];
		Sys.println(Std.string(a[0] + a[1]));
		Sys.println(Std.string(a[0] + a[1] + a[2] + 0.25));
		Sys.println(Std.string(a[1] - a[0]));
		Sys.println(Std.string(a[0] * a[1]));
		Sys.println(Std.string(a[1] / a[2] + 0.25));
		Sys.println(Std.string(a[1] % a[0]));
		Sys.println(Std.string(a[0] + c.get()));
		// Element sums stored in a local and passed straight to Sys.println.
		final floats:Array<Float> = [1.5, 2.25];
		final ints:Array<Int> = [2, 5];
		final floatSum:Float = floats[0] + floats[1];
		Sys.println(floatSum);
		Sys.println(floats[0] + floats[1]);
		final intSum:Int = ints[0] + ints[1];
		Sys.println(intSum);
		Sys.println(ints[0] + ints[1]);
		final mixedSum:Float = ints[0] + floats[0];
		Sys.println(mixedSum);
		Sys.println(floats[1] + ints[1]);
		// Mixed Int and Float, and Int / Int.
		final i = 7;
		Sys.println(Std.string(i + c.get()));
		Sys.println(Std.string(count() * a[2] + i));
		Sys.println(Std.string(i / 2));
		Sys.println(Std.string(count() / 2));
		Sys.println(Std.string(i % 4));
		// Comparisons.
		Sys.println(Std.string(c.get() > 1));
		Sys.println(Std.string(a[0] < a[1]));
		Sys.println(Std.string(g.value >= 4));
		Sys.println(Std.string(i <= c.get()));
		Sys.println(Std.string(c.get() == 1.25));
		Sys.println(Std.string(a[2] != g.get()));
		// Compound assignment on Float.
		var total = 0.25;
		total += c.get();
		total += a[1];
		total += count();
		total -= g.get() / 8;
		Sys.println(Std.string(total));
		c.v += a[0];
		Sys.println(Std.string(c.v));
		var f = 0.5;
		f = f + count();
		Sys.println(Std.string(f));
		c.bump(2);
		Sys.println(Std.string(c.v));
		c.v += count();
		Sys.println(Std.string(c.v));
		a[0] += count();
		Sys.println(Std.string(a[0]));
		// Float-backed abstract `this`.
		final m:Meters = 5.5;
		Sys.println(Std.string(m.half()));
		Sys.println(Std.string(m.plus(0.25)));
		Sys.println(Std.string(m.scaled(3)));
		Sys.println(Std.string(m.rest()));
		Sys.println(Std.string(m.longer(4.5)));
		// Float-valued if and switch with Int branches.
		Sys.println(Std.string(pick(true)));
		Sys.println(Std.string(pick(false)));
		Sys.println(Std.string(choose(0)));
		Sys.println(Std.string(choose(1)));
		// String + Float still concatenates.
		Sys.println("value: " + c.get());
		Sys.println("sum: " + (c.get() + 0.5));
		Sys.println(c.get() + " first");
		Sys.println("item " + a[1]);
		Sys.println("g " + g.value);
		// A String operand from a function-typed local still concatenates.
		final label:() -> String = () -> "n=";
		Sys.println(label() + count());
		Sys.println(label() + c.get());
		// A nullable Float operand: the product is a Float.
		final maybe:Null<Float> = 1.5;
		Sys.println(Std.string(maybe * 3));
		Sys.println(Std.string(maybe + 0.25));
		final boxed = new G<Null<Float>>(0.5);
		Sys.println(Std.string(boxed.get() + 0.25));
		Sys.println(Std.string(boxed.get() > 0.25));
		var steps:Null<Int> = 3;
		Sys.println(Std.string(steps / 2));
		Sys.println(Std.string(steps * 2 + 1));
		// Int and Float instance fields, read with and without `this.`.
		final p = new Point(3, 4, 1.25, 2.5);
		Sys.println(Std.string(p.sum()));
		Sys.println(Std.string(p.explicitSum()));
		Sys.println(Std.string(p.size()));
		Sys.println(Std.string(p.explicitSize()));
		Sys.println(Std.string(p.mixed()));
		Sys.println(Std.string(p.x + p.y));
		Sys.println(Std.string(p.w - p.h));
		// Arithmetic on a null Null<Float> raises a catchable error.
		final nothing:Null<Float> = null;
		try {
			Sys.println(Std.string(nothing * 3));
		} catch (error:Dynamic) {
			Sys.println("null arithmetic raised");
		}
		// A Float field written from a Float-valued if with an Int branch.
		c.v = if (i > 3) 1 else 0.25;
		Sys.println(Std.string(c.v + 0.5));
	}
}
