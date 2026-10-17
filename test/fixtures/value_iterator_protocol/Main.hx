/** Observe acquisition, loop control and closure lifetimes through ordinary value iterators. */
class Main {
	static var evaluations:Int = 0;
	static var selected:Values;

	static function source():Values {
		evaluations++;
		return selected;
	}

	static extern inline function sum(input:Values):Int {
		var result = 0;
		for (value in input)
			result += value;
		return result;
	}

	static function main():Void {
		selected = new Values(3);
		var total = 0;
		for (value in source())
			total += value;
		if (total != 6 || evaluations != 1 || selected.starts != 1 || selected.cursor.reads != 3 || selected.cursor.checks != 4)
			throw "value iteration must acquire once and read once per edge";
		selected = new Values(0);
		for (value in source())
			throw "empty iterator entered its body";
		if (selected.cursor.checks != 1 || selected.cursor.reads != 0)
			throw "empty iterator effects";
		selected = new Values(4);
		var visited = 0;
		for (value in source()) {
			if (value == 1)
				continue;
			if (value == 3)
				break;
			visited += value;
		}
		if (visited != 2 || selected.cursor.reads != 3 || selected.cursor.checks != 3)
			throw "value loop lost its break or continue destination";
		var direct = 0;
		for (value in new Both())
			direct += value;
		if (direct != 3)
			throw "direct iterator must take precedence over its factory";
		var fallback = 0;
		for (value in new Partial())
			fallback += value;
		if (fallback != 6)
			throw "invalid direct iterator must leave its valid factory available";
		final first = function():Int {
			for (value in new Values(3))
				return value + 10;
			return -1;
		};
		if (first() != 11)
			throw "iterator return must exit its original function";
		final closures:Array<Void->Int> = [];
		for (value in new Values(3))
			closures.push(function():Int {
				return value;
			});
		if (closures[0]() != 1 || closures[1]() != 2 || closures[2]() != 3)
			throw "iteration closures must retain separate bindings";
		selected = new Values(3);
		final before = evaluations;
		if (sum(source()) != 6 || sum(new Values(2)) != 3)
			throw "inline iterator values";
		if (evaluations != before + 1 || selected.starts != 1 || selected.cursor.reads != 3)
			throw "inline iterator duplicated its source or protocol calls";
	}
}

/** The source records factory calls independently from cursor operations. */
class Values {
	public final cursor:Cursor;
	public var starts:Int = 0;

	public function new(limit:Int)
		cursor = new Cursor(limit);

	public function iterator():Cursor {
		starts++;
		return cursor;
	}
}

/** One next call yields one Int and advances the cursor. */
class Cursor {
	final limit:Int;
	var position:Int = 0;

	public var reads:Int = 0;
	public var checks:Int = 0;

	public function new(limit:Int)
		this.limit = limit;

	public function hasNext():Bool {
		checks++;
		return position < limit;
	}

	public function next():Int {
		reads++;
		return ++position;
	}
}

/** A complete direct iterator wins over a second, observably different source. */
class Both extends Cursor {
	public function new()
		super(2);

	public function iterator():Cursor
		return new Cursor(5);
}

/** A non-Boolean direct condition does not hide a valid iterator factory. */
class Partial {
	public function new() {}

	public function hasNext():String
		return "invalid";

	public function next():Int
		return 100;

	public function iterator():Cursor
		return new Cursor(3);
}
