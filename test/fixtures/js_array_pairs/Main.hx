/** Array pair iteration observes integer indices and current length, including holes and mutation. */
class Main {
	static var calls:Int = 0;

	static function values():Array<Int> {
		calls++;
		return [10, 11, 12];
	}

	static function main():Void {
		var total = 0;
		for (key => value in values())
			total += key + value;
		if (total != 36 || calls != 1)
			throw "numeric keys or repeated iterable";
		var empty:Array<Int> = [];
		for (key => value in empty)
			throw "empty array visited";
		var sparse:Array<Null<Int>> = [];
		sparse[2] = 3;
		var visits = 0;
		var keys = 0;
		for (key => value in sparse) {
			visits++;
			keys += key;
			if (key < 2 && value != null)
				throw "hole value";
		}
		if (visits != 3 || keys != 3)
			throw "holes skipped";
		var growing = [4];
		var grown = 0;
		for (key => value in growing) {
			grown += value;
			if (key == 0)
				growing.push(5);
		}
		if (grown != 9)
			throw "growth ignored";
		var shrinking = [1, 2, 3];
		var shrunk = 0;
		for (key => value in shrinking) {
			shrunk += value;
			shrinking.pop();
			shrinking.pop();
		}
		if (shrunk != 1)
			throw "removed elements visited";
		var controlled = 0;
		for (key => value in [10, 11, 12, 13]) {
			if (key == 1)
				continue;
			if (key == 3)
				break;
			controlled += key + value;
		}
		if (controlled != 24)
			throw "loop control";
		var nested = function():Int {
			var sum = 0;
			for (key => value in [10, 11, 12])
				sum += key + value;
			return sum;
		};
		if (nested() != 36)
			throw "local function iteration";
		var collect = function(r:Array<Int>) {
			var collectedKeys:Array<Int> = [];
			var collectedValues:Array<Int> = [];
			for (key => value in r) {
				collectedKeys.push(key);
				collectedValues.push(value);
			}
			return {keys: collectedKeys, values: collectedValues};
		};
		var collected = collect([3, 2]);
		if (collected.keys.length != 2 || collected.keys[0] != 0 || collected.keys[1] != 1 || collected.values[0] != 3 || collected.values[1] != 2)
			throw "local pair collection";
	}
}
