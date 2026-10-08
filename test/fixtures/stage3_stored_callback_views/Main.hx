class Main {
	static function consume(value:Dynamic):Dynamic
		return value;

	static function relay(callback:Dynamic->Dynamic):Dynamic->Dynamic
		return callback;

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
	}
}
