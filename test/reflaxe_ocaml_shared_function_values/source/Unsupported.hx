/** Signatures that need distinct value or default-argument semantics before admission. */
class Unsupported {
	public static function optional(?value:Int):Void {}

	public static function defaultValue(value:Int = 3):Void {}

	public static function rest(...values:Int):Void {}

	public static function generic<T>(value:T):T
		return value;

	public static function nullable(value:Null<Bool>):Void {}

	public static function floating(value:Float):Void {}

	public static function earlyBranch(flag:Bool):Int {
		if (flag)
			return 3;
		return 9;
	}
}
