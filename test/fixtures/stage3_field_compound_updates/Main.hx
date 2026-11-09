typedef Point = {
	var x:Int;
	var y:Float;
	var tag:String;
}

class Holder {
	public var ratio:Float = 1.5;
	public var total:Float = 6.25;
	public var whole:Float = 10.5;

	public function new() {}

	public function addWithThis(n:Int):Void {
		this.total += n;
	}

	public function addBare(n:Int):Float {
		total += n;
		return total;
	}

	public function addAndReturn(n:Float):Float {
		return this.total += n;
	}
}

class Cell<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}
}

class Main {
	static var log = "";

	static function count():Int {
		log += "count;";
		return 3;
	}

	static function half():Float {
		log += "half;";
		return 0.5;
	}

	static function picked(h:Holder):Holder {
		log += "picked;";
		return h;
	}

	static function point(p:Point):Point {
		log += "point;";
		return p;
	}

	static function flushLog():Void {
		Sys.println(log);
		log = "";
	}

	static function main():Void {
		// Anonymous structures, statement position.
		var o = {n: 1};
		o.n += 2;
		Sys.println(o.n);
		o.n -= 5;
		Sys.println(o.n);
		o.n *= -3;
		Sys.println(o.n);

		// Anonymous structures, value position.
		final viaValue = (o.n += 4);
		Sys.println(viaValue);
		Sys.println(o.n);
		Sys.println((o.n -= 1) + 100);

		// Anonymous Float and String fields, also behind a typedef.
		final p:Point = {x: 7, y: 1.25, tag: "a"};
		p.y += 0.5;
		Sys.println(p.y);
		p.y -= 2;
		Sys.println(p.y);
		Sys.println(p.y *= 3);
		Sys.println(p.y /= 2);
		p.y += p.x;
		Sys.println(p.y);
		p.tag += "b";
		Sys.println(p.tag);
		Sys.println(p.tag += "c");
		Sys.println(p.tag += 1);

		// The receiver runs once and before the right operand.
		point(p).x += count();
		Sys.println(p.x);
		flushLog();
		Sys.println(point(p).y += half());
		flushLog();

		// Float instance fields, statement position.
		final h = new Holder();
		h.ratio -= 0.25;
		Sys.println(h.ratio);
		h.ratio += 2;
		Sys.println(h.ratio);
		h.ratio *= 1.5;
		Sys.println(h.ratio);
		h.ratio /= 3;
		Sys.println(h.ratio);

		// Int right operands.
		h.addWithThis(2);
		Sys.println(h.total);
		Sys.println(h.addBare(1));
		h.total += count();
		Sys.println(h.total);
		flushLog();

		// Float instance fields, value position.
		Sys.println(h.addAndReturn(0.25));
		final viaField = (h.whole -= 2.25);
		Sys.println(viaField);
		Sys.println(h.whole);
		Sys.println((h.whole += 1) * 2);
		h.whole %= 3;
		Sys.println(h.whole);

		// Receiver and right operand order on a Float instance field.
		picked(h).ratio += count();
		Sys.println(h.ratio);
		flushLog();
		Sys.println(picked(h).ratio -= half());
		flushLog();

		// A field declared with a type parameter and used at Float.
		final cell = new Cell<Float>(1.5);
		cell.value += 1;
		Sys.println(cell.value);
		cell.value -= 0.25;
		Sys.println(cell.value);
		Sys.println(cell.value *= 2);

		// Int remainder, and nullable right operands.
		final nf:Null<Float> = 0.125;
		final ni:Null<Int> = 2;
		p.x %= 4;
		Sys.println(p.x);
		o.n += ni;
		Sys.println(o.n);
		h.ratio += nf;
		Sys.println(h.ratio);
		Sys.println(h.ratio += ni);

		// Bitwise updates on an anonymous Int field.
		final bits = {n: 12};
		bits.n |= 3;
		Sys.println(bits.n);
		bits.n &= 13;
		Sys.println(bits.n);
		bits.n ^= 6;
		Sys.println(bits.n);
		bits.n <<= 4;
		Sys.println(bits.n);
		bits.n >>= 2;
		Sys.println(bits.n);
		bits.n = -16;
		bits.n >>>= 28;
		Sys.println(bits.n);
		Sys.println(bits.n |= 16);
		Sys.println((bits.n &= 21) + 100);
		point(p).x <<= count();
		Sys.println(p.x);
		flushLog();

		// The right operand sees the old stored value read first.
		final self = {n: 10};
		self.n += (self.n += 5);
		Sys.println(self.n);
		final sum = new Holder();
		sum.whole += (sum.whole -= 3.25);
		Sys.println(sum.whole);
	}
}
