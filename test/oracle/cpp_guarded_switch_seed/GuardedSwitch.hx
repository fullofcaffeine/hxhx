/** Generic payload types must stay attached to their selected enum declaration. */
enum GuardToken<T> {
	Pair(left:T, right:T);
	Empty;
}

/** Guards retry patterns without rereading observed elements or sharing captured locals. */
class GuardedSwitch {
	/** Both guard results return through the authored function, including a nested conditional. */
	public static function runtimeGuard(seed:Int, effect:Int->Bool):Int {
		switch seed {
			case value if (effect(value)):
				if (value == 2)
					return 7;
				else
					return 8;
			case _:
				return 9;
		}
	}

	/** A rejected non-exhaustive guard must still reach the statement after the switch. */
	public static function guardThenFallback(seed:Int, effect:Int->Bool):Int {
		switch seed {
			case value if (effect(value)):
				return 7;
		}
		return 9;
	}

	/** A true result keeps the guard's effects, and every selected arm returns directly. */
	public static function effectfulTrue(seed:Int, effect:Int->Bool):Int {
		switch seed {
			case 1 if ({
				effect(seed);
				true;
			}):
				return 7;
			case _:
				return 9;
		}
	}

	/** Dynamic condition conversion uses the checked guard occurrence, not the local's spelling. */
	public static function dynamicGuard(value:Dynamic):Int {
		return switch 1 {
			case 1 if (value): 1;
			case _: 0;
		};
	}

	public static function enumValue():GuardToken<Int> {
		return Pair(1, 2);
	}

	public static function enumSelect(value:GuardToken<Int>, accept:Int->Bool):Int {
		return switch value {
			case Pair(item, 2) | Pair(1, item) if (accept(item)): item;
			case _: 0;
		};
	}

	public static function record(value:{items:Array<Int>}):Int {
		return switch value {
			case {items: ([item, 2] | [1, item])} if (item == 2): item;
			case _: 0;
		};
	}

	public static function alternatives(values:Array<Int>, reject:(Void->Int)->Bool):Int {
		return switch values {
			case [value, 2] | [1, value] if (reject(function():Int {
				value++;
				return value;
			})): value;
			case _: 0;
		};
	}

	public static function scalar(seed:Int):Int {
		return switch seed {
			case 1 if (seed > 1): 11;
			case 1: 12;
			case _: 13;
		};
	}

	public static function observed(values:Array<Int>):Int {
		return switch values {
			case [1, value] if ({
				values[1] = 9;
				false;
			}): 100;
			case [1, value]: value;
			case _: -1;
		};
	}

	public static function capture(values:Array<Int>, reject:(Void->Int)->Bool):Void->Int {
		return switch values {
			case [1, value] if (reject(function():Int {
				value++;
				return value;
			})):
				function():Int {
					return 99;
				};
			case [1, value]: function():Int {
					return value;
				};
			case _: function():Int {
					return -1;
				};
		};
	}

	public static function retained(values:Array<Array<Int>>, reject:Void->Bool):Array<Int> {
		return switch values {
			case [value] if (reject()): null;
			case [value]: value;
			case _: null;
		};
	}

	public static function nested(seed:Int):Void->Int {
		return function():Int {
			return switch seed {
				case 1 if (false): 11;
				case 1: 12;
				case _: 13;
			};
		};
	}

	public static function loops():Int {
		var total = 0;
		for (index in 0...5) {
			switch index {
				case 1 if (index == 1):
					continue;
				case 3 if (index == 3):
					break;
				case _:
					total += index;
			}
		}
		return total;
	}
}
