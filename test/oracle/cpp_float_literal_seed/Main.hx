/** Authored Float constants shared by upstream observations and native-emitter tests. */
class Main {
	public static var zero:Float = 0.0;
	public static var negativeZero:Float = -0.0;
	public static var one:Float = 1.0;
	public static var tenth:Float = 0.1;
	public static var precision:Float = 1.2345678901234567;
	public static var adjacent:Float = 1.0000000000000002;
	public static var smallest:Float = 5e-324;
	public static var normal:Float = 2.2250738585072014e-308;
	public static var largest:Float = 1.7976931348623157e308;
	public static var negative:Float = -2147483648.0;

	public static var zzLocal:Float;
	public static var zzReturned:Float = returned();

	/** Exercise a signed, parenthesized literal through a local and return boundary. */
	static function returned():Float {
		final local:Float = -(0.1);
		return local;
	}

	public static function main():Void {
		final local:Float = 1.0000000000000002;
		zzLocal = local;
	}
}
