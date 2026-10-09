/** Real-source observations for callback locals whose complete use graph stays in this function. */
class Main {
	static function consume(value:Dynamic):Dynamic
		return value;

	static function main():Void {
		var source:Dynamic->Dynamic = consume;
		var first:Int->Dynamic = source;
		var second:Int->Dynamic = source;
		var alias = first;
		var direct:Int->Dynamic = consume;
		Sys.println(first(7));
		Sys.println(first == alias);
		Sys.println(first == second);
		Sys.println(first == source);
		Sys.println(direct(9));
		Sys.println(direct == source);
		var boolView:Bool->Bool = source;
		Sys.println(boolView(true));
		Sys.println(boolView(false));
		var number:Int->Int = value -> value + 1;
		var erased:Dynamic->Dynamic = number;
		Sys.println(erased(7));
		Sys.println(number == erased);
	}
}
