/** Separate-module static used to prove qualified OCaml ref-cell access. */
class ExternalHolder {
	public static var value:Int = 10;
	public static var omitted:Int;
	public static var omittedBool:Bool;
	public static var omittedNullableInt:Null<Int>;
	public static var omittedNullableBool:Null<Bool>;
}
