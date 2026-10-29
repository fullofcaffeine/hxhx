/** Branch results survive collecting effects without inventing a value on abrupt completion. */
class Main {
	static function select(read:Void->Int, produce:Int->Dynamic):Dynamic {
		final choice = switch (read()) {
			case 1 | 2: {produce(7);}
			case 3: produce(8);
			default: produce(9);
		};
		return choice;
	}

	static function conditional(flag:Bool, produce:Int->Dynamic):Dynamic {
		final choice = if (flag) {
			produce(4);
		} else {
			produce(5);
		};
		return choice;
	}

	static function early(flag:Bool, produce:Int->Dynamic):Dynamic {
		final choose = function():Dynamic {
			final choice = if (flag) {
				return produce(11);
			} else {
				produce(12);
			};
			return choice;
		};
		return choose();
	}

	static function strings(value:String):Int {
		return switch (value) {
			case "hit": 1;
			case null: 2;
			default: 3;
		};
	}

	static function bools(value:Bool):Int {
		return switch (value) {
			case true: 1;
			default: 2;
		};
	}

	static function defaultFirst(value:Int):Int {
		return switch (value) {
			default: 9;
			case 1: 1;
		};
	}

	static function nested(value:Int):Int {
		return switch (value) {
			case 1: switch (value + 1) {
					case 2: 7;
					default: 8;
				};
			default: 9;
		};
	}

	static function loop():Int {
		final run = function():Int {
			var index = 0;
			while (true) {
				switch (index) {
					case 0:
						index++;
						continue;
					default:
						break;
				}
			}
			return index;
		};
		return run();
	}

	static function main():Void {
		var reads = 0;
		var writes = 0;
		final value = select(function():Int {
			reads++;
			return 2;
		}, function(value:Int):Dynamic {
			writes++;
			return value;
		});
		Sys.println(value);
		Sys.println(reads);
		Sys.println(writes);
		Sys.println(conditional(false, function(value:Int):Dynamic {
			return value;
		}));
		Sys.println(early(true, function(value:Int):Dynamic {
			return value;
		}));
		Sys.println(strings(null));
		Sys.println(bools(false));
		Sys.println(defaultFirst(1));
		Sys.println(nested(1));
		Sys.println(loop());
	}
}
