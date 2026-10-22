/** Nullable branches use one selected result type and evaluate only the chosen arm. */
class Main {
	static function integer(flag:Bool):Null<Int>
		return flag ? 3 : null;

	static function reverseInteger(flag:Bool):Null<Int>
		return flag ? null : 4;

	static function boolean(flag:Bool):Null<Bool>
		return flag ? false : null;

	static function reverseBoolean(flag:Bool):Null<Bool>
		return flag ? null : true;

	static function integers():Void {
		if (integer(true) != 3 || integer(false) != null || reverseInteger(true) != null || reverseInteger(false) != 4)
			throw "nullable integer branch changed";
	}

	static function booleans():Void {
		if ("" + boolean(true) != "false" || boolean(false) != null || reverseBoolean(true) != null || "" + reverseBoolean(false) != "true")
			throw "nullable boolean branch changed";
	}

	static function effects():Void {
		var conditions = 0;
		var arms = 0;
		final condition = () -> {
			conditions++;
			return true;
		};
		final yes = () -> {
			arms++;
			return 9;
		};
		final no = function():Null<Int> {
			arms += 10;
			return null;
		};
		var selected:Null<Int> = condition() ? yes() : no();
		if (selected != 9 || conditions != 1 || arms != 1)
			throw "first branch evaluation changed";
		selected = !condition() ? yes() : (condition() ? no() : yes());
		if (selected != null || conditions != 3 || arms != 11)
			throw "nested branch evaluation changed";
	}

	static function main():Void {
		integers();
		booleans();
		effects();
	}
}
