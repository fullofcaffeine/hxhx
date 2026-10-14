import Math as Constants;
import shadows.Math;

/** Standard constants retain their declaration through aliases, locals, and initializers. */
class Main {
	public static var nan:Float = Constants.NaN;
	public static var negative:Float = Constants.NEGATIVE_INFINITY;
	public static var pi:Float = Constants.PI;
	public static var positive:Float = Constants.POSITIVE_INFINITY;
	public static var zLocal:Float;
	public static var zShadow:Float;

	public static function main():Void {
		final local:Float = Constants.PI;
		zLocal = local;
		zShadow = Math.PI;
	}
}
