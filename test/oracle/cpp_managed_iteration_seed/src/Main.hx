/** Array callbacks expose selection order, mutation, and captured iteration bindings. */
class Main {
	static function walk(source:Void->Array<Int>, visit:Int->Void):Int {
		final run = function():Int {
			var total = 0;
			for (value in source()) {
				if (value < 0)
					continue;
				if (value == 9)
					break;
				visit(value);
				total = total + value;
			}
			return total;
		};
		return run();
	}

	static function capture(values:Array<Int>, save:(Void->Int)->Void):Void {
		final run = function():Void {
			for (value in values)
				save(function():Int {
					return value;
				});
		};
		run();
	}

	static function nested(left:Array<Int>, right:Array<Int>):Int {
		final run = function():Int {
			var total = 0;
			for (a in left)
				for (b in right)
					total = total + a + b;
			return total;
		};
		return run();
	}

	static function first(values:Array<Int>):Int {
		final run = function():Int {
			for (value in values)
				return value;
			return -1;
		};
		return run();
	}

	static function main():Void {
		final values = [1, 2];
		var selected = 0;
		Sys.println(walk(function():Array<Int> {
			selected++;
			return values;
		}, function(value:Int):Void {
			if (value == 1) {
				values[1] = 7;
				values.push(4);
			}
		}));
		Sys.println(selected);
		Sys.println(walk(function():Array<Int> {
			return [-1, 2, 9, 99];
		}, function(_:Int):Void {}));
		Sys.println(walk(function():Array<Int> {
			return [];
		}, function(_:Int):Void {}));
		final saved:Array<Void->Int> = [];
		capture([4, 6], function(value:Void->Int):Void {
			saved.push(value);
		});
		Sys.println(saved[0]());
		Sys.println(saved[1]());
		Sys.println(nested([1, 2], [3, 4]));
		Sys.println(first([7, 8]));
		Sys.println(first([]));
		Sys.println(negate(-2147483648));
	}

	static function negate(value:Int):Int {
		return -value;
	}
}
