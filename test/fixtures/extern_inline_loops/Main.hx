/** Runtime assertions distinguish loop effects, nested destinations, and repeated expansion. */
class Main {
	static var events:Int = 0;

	static function limit():Int {
		events++;
		return 5;
	}

	static extern inline function sum(n:Int):Int {
		var total = 0;
		for (i in 0...n) {
			if (i == 1)
				continue;
			if (i == 4)
				break;
			total += i;
		}
		return total;
	}

	static extern inline function nested(n:Int):Int {
		var total = 0;
		for (i in 0...n) {
			for (j in 0...n) {
				if (j == 1)
					continue;
				if (j == 3)
					break;
				total += i + j;
			}
		}
		return total;
	}

	static extern inline function repeated(n:Int):Int {
		var i = 0;
		var total = 0;
		while (i < n) {
			i++;
			if (i == 2)
				continue;
			if (i == 5)
				break;
			total += i;
		}
		do {
			total++;
			i--;
			if (i == 4)
				continue;
		} while (i > 3);
		return total;
	}

	static function main():Void {
		if (sum(limit()) != 5 || events != 1)
			throw "for effects";
		if (sum(5) != 5 || nested(5) != 30)
			throw "nested or repeated destinations";
		if (repeated(6) != 10)
			throw "while and do-while control";
		var caller = 0;
		for (i in 0...2)
			caller += sum(5);
		if (caller != 10)
			throw "caller loop destination";
		if (pairs() != 36)
			throw "key and value bindings";
		var item = 99;
		var selected = select(limit());
		if (selected.length != 4 || selected[0] != 0 || selected[1] != 1 || selected[2] != 3 || selected[3] != 4 || events != 2 || item != 99)
			throw "comprehension effects or caller scope";
		if (select(2).length != 2 || select(0).length != 0)
			throw "repeated comprehension expansion";
		var grid = collect(3);
		if (grid.length != 6 || grid[0] != 0 || grid[1] != 2 || grid[2] != 10 || grid[3] != 12 || grid[4] != 20 || grid[5] != 22)
			throw "nested comprehension bindings";
		var text = repeat("kept", 2);
		var numbers = repeat(7, 1);
		if (text.length != 2 || text[0] != "kept" || text[1] != "kept" || numbers.length != 1 || numbers[0] != 7)
			throw "generic comprehension element type";
		var entries = collectPairs();
		if (entries.length != 2 || entries[0] != 10 || entries[1] != 12)
			throw "comprehension key and value bindings";
	}

	/** Expression-form iteration needs the same fresh scope as statement loops. */
	static extern inline function select(item:Int):Array<Int>
		return [for (item in 0...item) if (item != 2) item];

	static extern inline function collect(n:Int):Array<Int>
		return [
			for (outer in 0...n)
				for (item in 0...n)
					if (item != 1)
						outer * 10 + item
		];

	static extern inline function repeat<T>(value:T, n:Int):Array<T>
		return [for (item in 0...n) value];

	static extern inline function collectPairs():Array<Int>
		return [for (key => value in [10, 11]) key + value];

	static extern inline function pairs():Int {
		var total = 0;
		for (key => value in [10, 11, 12])
			total += key + value;
		return total;
	}
}
