/** Empty braces must allocate distinct object values at an ordinary argument boundary. */
class Main {
	static function store(value:Dynamic, answer:Int):Dynamic {
		value.answer = answer;
		return value;
	}

	static function main():Void {
		var first = store({}, 7);
		var second = store(({}), 11);
		Sys.println(first.answer);
		Sys.println(second.answer);
		Sys.println(first == second);
	}
}
