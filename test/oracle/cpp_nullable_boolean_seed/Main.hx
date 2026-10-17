/** Condition reads preserve nullable values and evaluate only the selected effects. */
class Main {
	static var effects:Int = 0;

	static function condition(value:Null<Bool>, digit:Int):Null<Bool> {
		effects = effects * 10 + digit;
		return value;
	}

	static function branch(digit:Int):Int {
		effects = effects * 10 + digit;
		return digit;
	}

	static function exercise(value:Null<Bool>, expected:Int, absent:Bool):Void {
		final selected = expected == 1 ? 2 : 3;
		final order = expected == 1 ? 12 : 13;
		effects = 0;
		final result = condition(value, 1) ? branch(2) : branch(3);
		if (result != selected || effects != order)
			throw "nullable ternary changed effects";
		effects = 0;
		if (condition(value, 1))
			branch(2);
		else
			branch(3);
		if (effects != order)
			throw "nullable if changed effects";
		effects = 0;
		while (condition(value, 1)) {
			branch(2);
			break;
		}
		if (effects != (expected == 1 ? 12 : 1))
			throw "nullable while changed effects";
		effects = 0;
		do {
			branch(2);
		} while (condition(null, 1));
		if (effects != 21)
			throw "nullable do while repeated";
		effects = 0;
		final negated = !condition(value, 1) ? branch(3) : branch(2);
		if (negated != selected || effects != order)
			throw "nullable negation changed effects";
		if (absent && value != null)
			throw "condition changed absent source";
		if (!absent && value == null)
			throw "condition changed present source";
	}

	static function main():Void {
		exercise(null, 0, true);
		exercise(false, 0, false);
		exercise(true, 1, false);
		logical(null, null, false, false, 1, 12);
		logical(null, false, false, false, 1, 12);
		logical(null, true, false, true, 1, 12);
		logical(false, null, false, false, 1, 12);
		logical(false, false, false, false, 1, 12);
		logical(false, true, false, true, 1, 12);
		logical(true, null, false, true, 12, 1);
		logical(true, false, false, true, 12, 1);
		logical(true, true, true, true, 12, 1);
		effects = 0;
		if (negatedReturn(true) || effects != 1)
			throw "negation changed an early return";
		effects = 0;
		if (!negatedReturn(false) || effects != 2)
			throw "negation lost its completing operand";
		effects = 0;
		if (condition(false, 1) && fail())
			throw "false AND selected true";
		if (!(condition(true, 2) || fail()) || effects != 12)
			throw "short circuit evaluated a throwing operand";
	}

	/** A return inside a condition operand exits this function before negation executes. */
	static function negatedReturn(early:Bool):Bool {
		return !(if (early) {
			effects = 1;
			return false;
		} else {
			effects = 2;
			false;
		});
	}

	static function fail():Bool
		throw "selected operand";

	/** The independent table specifies truth and left/right evaluation order for all nullable input pairs. */
	static function logical(left:Null<Bool>, right:Null<Bool>, expectedAnd:Bool, expectedOr:Bool, andEvents:Int, orEvents:Int):Void {
		effects = 0;
		var actual = false;
		if (condition(left, 1) && condition(right, 2))
			actual = true;
		if (actual != expectedAnd || effects != andEvents)
			throw "nullable AND condition changed truth or effects";
		effects = 0;
		actual = false;
		if (condition(left, 1) || condition(right, 2))
			actual = true;
		if (actual != expectedOr || effects != orEvents)
			throw "nullable OR condition changed truth or effects";
		effects = 0;
		final selected = (condition(left, 1) && condition(right, 2)) ? 1 : 0;
		if (selected != (expectedAnd ? 1 : 0) || effects != andEvents)
			throw "nullable logical ternary changed selection";
		effects = 0;
		actual = false;
		while (!(condition(left, 1) || condition(right, 2))) {
			actual = true;
			break;
		}
		if (actual == expectedOr || effects != orEvents)
			throw "nullable logical while or negation changed effects";
		effects = 0;
		var iterations = 0;
		do {
			iterations++;
			if (iterations == 2)
				break;
		} while (condition(left, 1) && condition(right, 2));
		if (iterations != (expectedAnd ? 2 : 1) || effects != andEvents)
			throw "nullable logical do while changed effects";
		// Callback calls use rooted result transport even with a concrete Bool signature.
		final readLeft:() -> Bool = function():Bool return condition(left, 1);
		final readRight:() -> Bool = function():Bool return condition(right, 2);
		effects = 0;
		actual = false;
		if (readLeft() && readRight())
			actual = true;
		if (actual != expectedAnd || effects != andEvents)
			throw "callback AND changed truth or effects";
		effects = 0;
		if (!(readLeft() || readRight()) != !expectedOr || effects != orEvents)
			throw "callback OR or negation changed truth or effects";
	}
}
