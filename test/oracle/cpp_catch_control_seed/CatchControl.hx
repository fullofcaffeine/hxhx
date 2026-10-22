/** Carrier catches preserve payload identity and the surrounding function and loop destinations. */
class CatchControl {
	public static function any(seed:Any):Any {
		try {
			throw seed;
		} catch (value:Any) {
			return value;
		}
	}

	public static function select(seed:Dynamic):Dynamic {
		try {
			throw seed;
		} catch (value:Dynamic) {
			return value;
		}
	}

	public static function expression(seed:Dynamic):Dynamic {
		return try {
			throw seed;
		} catch (value:Dynamic) {
			value;
		};
	}

	public static function nested(seed:Dynamic):Dynamic {
		try {
			try {
				throw seed;
			} catch (inner:Dynamic) {
				throw inner;
			}
		} catch (outer:Dynamic) {
			return outer;
		}
	}

	public static function capture(seed:Dynamic):Dynamic->Dynamic {
		try {
			throw seed;
		} catch (state:Dynamic) {
			return function(next:Dynamic):Dynamic {
				final previous = state;
				state = next;
				return previous;
			};
		}
	}

	public static function inside(seed:Dynamic):Void->Dynamic {
		return function():Dynamic {
			try {
				throw seed;
			} catch (value:Dynamic) {
				return value;
			}
		};
	}

	public static function loops():Int {
		var sum = 0;
		for (index in 0...5) {
			try {
				throw index;
			} catch (value:Dynamic) {
				if (index == 1)
					continue;
				if (index == 3)
					break;
				sum += index;
			}
		}
		return sum;
	}
}
