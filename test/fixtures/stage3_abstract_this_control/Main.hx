// Abstract constructors whose `this = value` takes its value from control flow, built natively and compared with upstream Haxe.

/** `this = if ...` picks the backing value from a branch. */
abstract Pick(Int) {
	public function new(n:Int)
		this = if (n > 0) n else -n;

	public function get():Int
		return this;
}

/** `this = cond ? a : b` already lowered without control steps; keep it working. */
abstract Sign(Int) {
	public function new(n:Int)
		this = n >= 0 ? 1 : -1;

	public function get():Int
		return this;
}

/** `this = switch ...` with a guard and a default. */
abstract Grade(String) {
	public function new(score:Int)
		this = switch score {
			case 10: "perfect";
			case s if (s >= 5): "pass";
			case _: "fail";
		};

	public function get():String
		return this;
}

/** `this = [for ...]` builds the backing array through a comprehension. */
abstract Squares(Array<Int>) {
	public function new(n:Int)
		this = [for (i in 0...n) i * i];

	public function sum():Int {
		var total = 0;
		for (value in this)
			total += value;
		return total;
	}

	public function size():Int
		return this.length;
}

/** Nested control: a switch inside an if branch, with a block that runs statements first. */
abstract Bucket(Int) {
	public function new(n:Int, wide:Bool) {
		Sys.println("bucket " + n);
		this = if (wide) {
			final doubled = n * 2;
			switch doubled {
				case 0: 0;
				case d if (d > 10): 100;
				case d: d;
			}
		} else if (n < 0) -1 else n;
	}

	public function get():Int
		return this;
}

/** A Float backing value chosen by control flow keeps its Float carrier. */
abstract Ratio(Float) {
	public function new(num:Float, den:Float)
		this = if (den == 0) 0.5 else switch num {
			case 0: 0.25;
			case _: num / den;
		};

	public function get():Float
		return this;
}

/** A Float abstract whose branches mix an Int-by-Float product and a Float literal. */
abstract Scale(Float) {
	public function new(level:Int)
		this = if (level > 1) level * 1.5 else 1.25;

	public function get():Float
		return this;
}

/** A compound assignment whose right side is control flow updates the Int slot once. */
abstract Steps(Int) {
	public function new(n:Int) {
		this = n;
		this *= switch n {
			case 0: 100;
			case _: if (n > 0) 2 else -3;
		};
	}

	public function get():Int
		return this;
}

/** The Float version of a control-valued compound assignment. */
abstract Offset(Float) {
	public function new(base:Float, up:Bool) {
		this = base;
		this += if (up) 1.5 else switch base {
			case 0: 2.5;
			case _: -0.5;
		};
	}

	public function get():Float
		return this;
}

/** `this = try ... catch ...` keeps the caught branch's value. */
abstract Safe(Int) {
	public function new(s:String)
		this = try {
			if (s == "")
				throw "empty";
			s.length;
		} catch (e:String)
			-1;

	public function get():Int
		return this;
}

/** A closure created in the constructor writes a control-valued `this`. */
abstract Late(Int) {
	public function new(n:Int) {
		final set = (v:Int) -> this = if (v > 0) v else 0;
		set(n);
	}

	public function get():Int
		return this;
}

/** The right side reads the value assigned to `this` so far. */
abstract Grow(Int) {
	public function new(n:Int, c:Bool) {
		this = n;
		this = if (c) this + 1 else this;
	}

	public function get():Int
		return this;
}

/** A compound update reads `this` before its right side writes `this`, and writes once at the end. */
abstract Rewrite(Int) {
	public function new(c:Bool) {
		this = 10;
		this += if (c) {
			this = 100;
			1;
		} else 2;
	}

	public function get():Int
		return this;
}

/** Control-valued `this` writes used as values. */
abstract Stored(Int) {
	public function new(c:Bool) {
		final stored = (this = if (c) 3 else 4);
		Sys.println("stored " + stored);
		final again = (this += switch c {
			case true: 10;
			case false: 20;
		});
		Sys.println("again " + again);
		final steps = [for (i in 0...2) (this = if (c) this + i else this - i)];
		Sys.println("steps " + steps.join(","));
	}

	public function get():Int
		return this;
}

class Main {
	static function main() {
		Sys.println(new Pick(-4).get());
		Sys.println(new Pick(7).get());
		Sys.println(new Sign(-3).get());
		Sys.println(new Sign(3).get());
		Sys.println(new Grade(10).get());
		Sys.println(new Grade(6).get());
		Sys.println(new Grade(2).get());
		final squares = new Squares(5);
		Sys.println(squares.size() + " " + squares.sum());
		Sys.println(new Squares(0).size());
		Sys.println(new Bucket(0, true).get());
		Sys.println(new Bucket(3, true).get());
		Sys.println(new Bucket(9, true).get());
		Sys.println(new Bucket(-2, false).get());
		Sys.println(new Bucket(4, false).get());
		Sys.println(new Ratio(3, 0).get());
		Sys.println(new Ratio(0, 2).get());
		Sys.println(new Ratio(3, 4).get());
		Sys.println(new Scale(3).get());
		Sys.println(new Scale(0).get());
		Sys.println(new Steps(0).get());
		Sys.println(new Steps(4).get());
		Sys.println(new Steps(-4).get());
		Sys.println(new Offset(1, true).get());
		Sys.println(new Offset(0, false).get());
		Sys.println(new Offset(3, false).get());
		Sys.println(new Safe("abc").get());
		Sys.println(new Safe("").get());
		Sys.println(new Late(5).get());
		Sys.println(new Late(-5).get());
		Sys.println(new Grow(4, true).get());
		Sys.println(new Grow(4, false).get());
		Sys.println(new Rewrite(true).get());
		Sys.println(new Rewrite(false).get());
		Sys.println(new Stored(true).get());
		Sys.println(new Stored(false).get());
	}
}
