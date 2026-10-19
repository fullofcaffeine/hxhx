/** Observe the selected callable before an argument replaces its mutable binding. */
class Main {
	static function pair(left:Int, right:Int):Int
		return left * 10 + right;

	static function other(left:Int, right:Int):Int
		return 100 + left + right;

	static function number(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}

	static function main():Void {
		var selected:Int->Int->Int = pair;
		function replace():Int {
			selected = other;
			Sys.println("replace");
			return 1;
		}
		Sys.println(selected(replace(), number("right", 2)));
		Sys.println(selected(1, 2));
	}
}
