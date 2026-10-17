/** Record operand effects even when their enclosing expression has no consumer. */
class Main {
	public static var log:Int = 0;

	static function mark(value:Int):Int {
		log = log * 10 + value;
		return value;
	}

	public static function main():Void {
		mark(1) + mark(2);
		mark(3) * mark(4);
	}
}
