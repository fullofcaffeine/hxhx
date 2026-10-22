/** Preserve nullable call arguments and branch results through the shared target. */
class Main {
	public static function select(flag:Bool, value:Int):Null<Int>
		return flag ? value : null;

	public static function recover(value:Null<Int>):Int
		return value == null ? 9 : value;

	public static function direct(flag:Bool):Int
		return recover(flag ? 3 : null);

	public static function retained(value:Null<Int>):Null<Int> {
		final copy = value;
		return copy;
	}

	static function main():Void {
		direct(true);
		direct(false);
		recover(retained(select(true, 0)));
		recover(retained(select(false, 0)));
	}
}
