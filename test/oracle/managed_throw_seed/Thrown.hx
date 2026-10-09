/** Values must survive the generated throw operand's scope without changing their type or identity. */
class Thrown {
	public static function text():Void {
		throw "problem";
	}

	public static function integer():Void {
		throw 7;
	}

	public static function array():Void {
		throw [1, 2];
	}

	public static function callback():Void {
		var count = 0;
		throw function() {
			count = count + 1;
			return count;
		};
	}

	public static function throwingCallback():Void {
		final callback = function():Int {
			throw 11;
		};
		throw callback;
	}

	public static function operand(callback:Void->Int):Void {
		throw callback();
	}
}
