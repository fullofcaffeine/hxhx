/** Function conversions and returns preserve source identity independently of native closure sharing. */
class Main {
	static function consume(value:Dynamic):Dynamic
		return value;

	static function relay(callback:Dynamic->Dynamic):Dynamic->Dynamic
		return callback;

	static function declared(value:Int):Int
		return value + 1;

	static function literal():Int->Int
		return value -> value + 1;

	static function captured(offset:Int):Int->Int
		return value -> value + offset;

	static function preserve(callback:Int->Int):Int->Int
		return callback;

	static function staticCallback():Int->Int
		return declared;

	static function forwarded():Int->Int
		return literal();

	static function main():Void {
		var source:Dynamic->Dynamic = consume;
		var first:Int->Dynamic = source;
		var second:Int->Dynamic = source;
		var alias = first;
		Sys.println(first(7));
		Sys.println(first == alias);
		Sys.println(first == second);
		Sys.println(first == source);
		var higherSource:(Dynamic->Dynamic)->(Dynamic->Dynamic) = relay;
		var higherView:(Int->Int)->(Int->Int) = higherSource;
		var number:Int->Int = value -> value + 1;
		var returned = higherView(number);
		Sys.println(returned(7));
		Sys.println(returned == number);
		var firstLiteral = literal();
		var secondLiteral = literal();
		var firstCapture = captured(1);
		var secondCapture = captured(1);
		Sys.println(declared == declared);
		Sys.println(firstLiteral == firstLiteral);
		Sys.println(firstLiteral == secondLiteral);
		Sys.println(firstCapture == secondCapture);
		Sys.println(firstLiteral(7));
		Sys.println(secondLiteral(7));
		var direct:Int->Dynamic = consume;
		Sys.println(direct(7));
		Sys.println(direct == source);
		var preserved = preserve(firstLiteral);
		Sys.println(preserved == firstLiteral);
		Sys.println(preserved(7));
		Sys.println(staticCallback() == declared);
		Sys.println(staticCallback() == staticCallback());
		var firstForwarded = forwarded();
		var secondForwarded = forwarded();
		Sys.println(firstForwarded != secondForwarded);
		Sys.println(firstForwarded(7));
	}
}
