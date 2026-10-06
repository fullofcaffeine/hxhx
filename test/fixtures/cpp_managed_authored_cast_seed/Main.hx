/** Explicit casts unwrap abstract storage without granting an implicit output conversion. */
class Main {
	public static var argumentResult:Int;
	public static var boxed:Box<Int> = 7;
	public static var calls:Int;
	public static var direct:Int = (cast boxed);
	public static var hidden:Hidden<Int> = cast 11;
	public static var localResult:Int;
	public static var nested:Outer<Int> = cast 13;
	public static var nestedResult:Int = cast nested;
	public static var once:Int = cast next();
	public static var returnResult:Int;

	static function next():Box<Int> {
		calls = calls + 1;
		return 7;
	}

	static function accept(value:Int):Int {
		return value;
	}

	static function unbox(value:Box<Int>):Int {
		return cast value;
	}

	public static function main():Void {
		var local:Int = cast hidden;
		local = cast hidden;
		localResult = local;
		direct = (cast boxed);
		argumentResult = accept(cast boxed);
		returnResult = unbox(boxed) + unbox(cast 7);
	}
}

/** Input is implicit; output requires an authored cast. */
abstract Box<T>(T) from T {}

/** No implicit conversions are declared. */
abstract Hidden<T>(T) {}

/** Storage resolution must substitute each distinct abstract declaration's parameter. */
abstract Outer<T>(Hidden<T>) {}
