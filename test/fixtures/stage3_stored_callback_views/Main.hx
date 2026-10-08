class Main {
	static function consume(value:Dynamic):Dynamic
		return value;

	static function main():Void {
		var source:Dynamic->Dynamic = consume;
		var first:Int->Dynamic = source;
		var second:Int->Dynamic = source;
		var alias = first;
		Sys.println(first(7));
		Sys.println(first == alias);
		Sys.println(first == second);
		Sys.println(first == source);
	}
}
