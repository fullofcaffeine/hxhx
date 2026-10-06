/** Initialization must evaluate the operand once before publishing its abstract value. */
class Main {
	public static var calls:Int;
	public static var mirror:Box<Int>;
	public static var value:Box<Int> = next();

	static function next():Int {
		calls = calls + 1;
		return 7;
	}

	public static function main():Void {
		mirror = value;
	}
}

/** Only the declared generic header authorizes Int input and output conversions. */
abstract Box<T>(T) from T to T {}
