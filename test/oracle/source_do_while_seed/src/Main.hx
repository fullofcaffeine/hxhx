/** Observe source do/while control without an introduced helper function. */
class Main {
	static function direct() {
		final value = {
			return 13;
			99;
		};
		return value;
	}

	static function returned():Int {
		final value = {
			do {
				return 7;
			} while (false);
			99;
		};
		return value;
	}

	static function main():Void {
		var rounds = 0;
		var checks = 0;
		var sum = 0;
		final value = {
			do {
				rounds++;
				if (rounds == 1)
					continue;
				if (rounds == 3)
					break;
				sum += rounds;
			} while (++checks < 5);
			sum;
		};
		var once = 0;
		final first = {
			do {
				once++;
			} while (false);
			once;
		};
		Sys.println("value=" + value);
		Sys.println("rounds=" + rounds);
		Sys.println("checks=" + checks);
		Sys.println("once=" + first);
		Sys.println("returned=" + returned());
		final nested = function():Int {
			do {
				return 11;
			} while (false);
			return 99;
		};
		Sys.println("nested=" + nested());
		Sys.println("direct=" + direct());
	}
}
