/** Deep concrete arithmetic must compile without repeatedly rendering discarded paths. */
class Main {
	static function sum(value:Int):Int {
		return value + (value + (value + (value + (value + (value + (value + (value + (value + (value + (value + (value + value)))))))))));
	}

	static function input(value:Int):Int {
		Sys.println("input");
		return value;
	}

	static function main():Void {
		Sys.println(sum(input(2)));
	}
}
