/** Required expansion must preserve callback-local returns and shared captured storage. */
class Main {
	static function invoke(callback:Int->Int):Int
		return callback(3);

	static extern inline function sum<T>(value:T, read:T->Int):Int {
		var total = read(value);
		var callback = function(delta:Int):Int {
			total += delta;
			return total;
		};
		return invoke(callback) + callback(1);
	}

	static function main():Void {
		var total = 99;
		if (sum(4, function(value:Int):Int return value) != 15)
			throw "captured storage or callback return";
		if (sum(10, function(value:Int):Int return value) != 27)
			throw "repeated expansion identities";
		if (total != 99)
			throw "caller binding changed";
		var first = retain("first");
		var second = retain("second");
		if (first() != "first" || second() != "second")
			throw "generic returned capture";
		if (defaulted(7) != 12)
			throw "callback default argument";
		if (recursive(5) != 120)
			throw "named callback recursion";
		if (nested(4)()() != 4)
			throw "forwarded nested capture";
		if (looped(6) != 8)
			throw "callback loop destinations";
	}

	static extern inline function retain<T>(value:T):Void->T {
		return function():T return value;
	}

	static extern inline function defaulted(value:Int):Int {
		var callback = function(delta:Int = 5):Int return value + delta;
		return callback();
	}

	static extern inline function recursive(value:Int):Int {
		function factorial(n:Int):Int {
			if (n <= 1)
				return 1;
			return n * factorial(n - 1);
		}
		return factorial(value);
	}

	static extern inline function nested<T>(value:T):Void->(Void->T) {
		return function():Void->T return function():T return value;
	}

	static extern inline function looped(limit:Int):Int {
		var callback = function():Int {
			var index = 0;
			var sum = 0;
			while (index < limit) {
				index++;
				if (index == 2)
					continue;
				if (index == 5)
					break;
				sum += index;
			}
			return sum;
		};
		return callback();
	}
}
