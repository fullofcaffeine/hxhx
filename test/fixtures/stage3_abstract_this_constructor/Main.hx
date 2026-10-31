/** Abstract constructors that assign `this`, built natively and compared with upstream Haxe. */
abstract Bag(Map<String, Int>) {
	public function new()
		this = new Map();

	public function add(key:String):Void
		this.set(key, 1);

	public function has(key:String):Bool
		return this.exists(key);
}

/** A constructor with arguments that assigns `this` after other statements. */
abstract Tally(Map<String, Int>) {
	public function new(first:String, count:Int) {
		final seed = new Map<String, Int>();
		seed.set(first, count);
		Sys.println("tally seeded with " + first);
		this = seed;
		this.set("total", count);
	}

	public function bump(key:String):Void {
		final current = this.exists(key) ? this.get(key) : 0;
		this.set(key, current + 1);
	}

	public function read(key:String):Int
		return this.exists(key) ? this.get(key) : -1;
}

abstract Stack(Array<Int>) {
	public function new(initial:Int) {
		this = [];
		this.push(initial);
	}

	public function push(value:Int):Void
		this.push(value);

	public function size():Int
		return this.length;

	public function top():Int
		return this[this.length - 1];

	public static function of(first:Int, second:Int):Stack {
		final stack = new Stack(first);
		stack.push(second);
		return stack;
	}
}

abstract Meters(Float) {
	public function new(value:Float)
		this = value * 2;

	public function value():Float
		return this;
}

class Counter {
	public var count:Int;

	public function new(start:Int)
		count = start;
}

abstract Clicker(Counter) {
	public function new(start:Int) {
		final counter = new Counter(start);
		counter.count += 10;
		this = counter;
	}

	public function click():Int {
		this.count += 1;
		return this.count;
	}
}

/** The last assignment wins, and an early `return` keeps the value already assigned. */
abstract Label(String) {
	public function new(text:String, upper:Bool) {
		this = text;
		if (!upper)
			return;
		this = text.toUpperCase();
	}

	public function show():String
		return "<" + this + ">";
}

/** Optional and default arguments, and an implicit method call after `this` is assigned. */
abstract Scores(Map<String, Int>) {
	public function new(?first:String, points:Int = 2) {
		this = new Map();
		if (first != null)
			record(first, points);
	}

	public function record(name:String, points:Int):Void
		this.set(name, points);

	public function score(name:String):Int
		return this.exists(name) ? this.get(name) : -1;
}

class Main {
	static final shared = new Scores("static");

	static function main() {
		final bag = new Bag();
		bag.add("a");
		Sys.println("bag has a=" + bag.has("a") + " b=" + bag.has("b"));

		final tally = new Tally("x", 3);
		tally.bump("x");
		tally.bump("y");
		Sys.println("tally x=" + tally.read("x") + " y=" + tally.read("y") + " total=" + tally.read("total") + " z=" + tally.read("z"));

		final stack = new Stack(4);
		stack.push(7);
		Sys.println("stack size=" + stack.size() + " top=" + stack.top());
		final built = Stack.of(1, 2);
		Sys.println("built size=" + built.size() + " top=" + built.top());

		final meters = new Meters(1.25);
		Sys.println("meters=" + meters.value());

		final clicker = new Clicker(5);
		clicker.click();
		Sys.println("clicker=" + clicker.click());

		Sys.println(new Label("quiet", false).show() + " " + new Label("loud", true).show());

		final text = new Box("text");
		final number = new Box(41);
		Sys.println("box=" + text.unwrap() + " " + (number.unwrap() + 1));

		Sys.println("scores " + new Scores("a",
			5).score("a") + " " + new Scores("b").score("b") + " " + new Scores().score("a") + " " + shared.score("static"));
	}
}
