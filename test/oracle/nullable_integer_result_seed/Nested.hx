/** Nested nullable operands still produce Int; their written source types remain distinct. */
class Nested {
	static function check(actual:Int, expected:Int):Void {
		if (actual != expected)
			throw "nested nullable arithmetic changed";
	}

	static function main():Void {
		var left:Null<Null<Int>> = 7;
		var right:Null<Null<Int>> = 3;
		var sum = left + right;
		var difference = left - right;
		var product = left * right;
		var remainder = left % right;
		check(sum, 10);
		check(difference, 4);
		check(product, 21);
		check(remainder, 1);
	}
}
