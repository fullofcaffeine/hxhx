/** Every arithmetic result must retain Int through an inferred local and a named call. */
class Main {
	static function check(value:Int, expected:Int):Void {
		if (value != expected)
			throw "integer result changed";
	}

	static function main():Void {
		var left:Null<Int> = 7;
		var right:Null<Int> = 3;
		var sum = left + 2;
		check(sum, 9);
		check(2 + left, 9);
		check(left + right, 10);
		var difference = left - 2;
		check(difference, 5);
		check(2 - left, -5);
		check(left - right, 4);
		var product = left * 2;
		check(product, 14);
		check(2 * left, 14);
		check(left * right, 21);
		var remainder = left % 2;
		check(remainder, 1);
		check(2 % left, 2);
		check(left % right, 1);
	}
}
