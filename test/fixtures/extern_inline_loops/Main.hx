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
	}

	static extern inline function pairs():Int {
		var total = 0;
		for (key => value in [10, 11, 12])
			total += key + value;
		return total;
	}
}
