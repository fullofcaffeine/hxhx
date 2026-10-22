/** A custom iterator exposes precise Int pairs and observable protocol calls. */
class Main {
	static var evaluations:Int = 0;
	static var selected:Pairs;

	static function source():Pairs {
		evaluations++;
		return selected;
	}

	/** A return in a statement loop exits the original function. */
	static function first():Int {
		for (key => value in new Pairs(3))
			return key + value + 7;
		return -1;
	}

	/** Required inlining must clone the selected protocol and both loop bindings. */
	static extern inline function sumPairs(pairs:Pairs):Int {
		var sum = 0;
		for (key => value in pairs)
			sum += key + value;
		return sum;
	}

	static function main():Void {
		selected = new Pairs(3);
		var total = 0;
		for (key => value in source())
			total += key + value;
		if (total != 33 || evaluations != 1 || selected.starts != 1 || selected.cursor.reads != 3 || selected.cursor.checks != 4)
			throw "iterator protocol or evaluation count";
		selected = new Pairs(0);
		for (key => value in source())
			throw "empty iterator body";
		if (selected.cursor.checks != 1 || selected.cursor.reads != 0)
			throw "empty iterator protocol";
		selected = new Pairs(4);
		var visited = 0;
		for (key => value in source()) {
			if (key == 0)
				continue;
			if (key == 2)
				break;
			visited += value;
		}
		if (visited != 10 || selected.cursor.reads != 3)
			throw "loop destinations";
		var direct = 0;
		for (key => value in new Cursor(3))
			direct++;
		var both = 0;
		for (key => value in new Both())
			both++;
		var fallback = 0;
		for (key => value in new Partial())
			fallback++;
		if (direct != 3 || both != 1 || fallback != 2)
			throw "direct iterator selection precedence";
		final local = function():Int {
			for (key => value in new Pairs(3))
				return key + value + 9;
			return -1;
		};
		if (first() != 7 || local() != 9)
			throw "key/value return destinations";
		final closures:Array<Void->Int> = [];
		for (key => value in new Pairs(3))
			closures.push(function():Int {
				return key + value;
			});
		if (closures[0]() != 0 || closures[1]() != 11 || closures[2]() != 22)
			throw "each loop closure must retain its own iteration bindings";
		selected = new Pairs(3);
		final evaluationsBefore = evaluations;
		if (sumPairs(source()) != 33 || sumPairs(new Pairs(2)) != 11)
			throw "required inline iterator results";
		if (evaluations != evaluationsBefore + 1 || selected.starts != 1 || selected.cursor.reads != 3)
			throw "required inline iterator duplicated an argument or protocol call";
	}
}

/** The source owns acquisition; its cursor owns iteration state. */
class Pairs {
	public final cursor:Cursor;
	public var starts:Int = 0;

	public function new(limit:Int) {
		cursor = new Cursor(limit);
	}

	public function keyValueIterator():Cursor {
		starts++;
		return cursor;
	}
}

/** Each next result is one typed record; hasNext has independently counted effects. */
class Cursor {
	final limit:Int;
	var position:Int = 0;

	public var reads:Int = 0;
	public var checks:Int = 0;

	public function new(limit:Int) {
		this.limit = limit;
	}

	public function hasNext():Bool {
		checks++;
		return position < limit;
	}

	public function next():{key:Int, value:Int} {
		reads++;
		final key = position++;
		return {key: key, value: key * 10};
	}
}

/** A valid direct protocol takes precedence over an iterable factory. */
class Both extends Cursor {
	public function new()
		super(1);

	public function keyValueIterator():Cursor
		return new Cursor(2);
}

/** An invalid direct condition leaves the valid factory available for selection. */
class Partial {
	public function new() {}

	public function hasNext():String
		return "bad";

	public function next():{key:Int, value:Int}
		return {key: 0, value: 0};

	public function keyValueIterator():Cursor
		return new Cursor(2);
}
