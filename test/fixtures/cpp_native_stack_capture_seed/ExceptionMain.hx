/** Observe raw exception snapshots through the real API before and after authored throws. */
class ExceptionMain {
	// These API results remain opaque to Haxe; the native observer validates their layout.
	public static var initial:Any;
	public static var chooseSecond:Bool;

	public static function observe():Any {
		return haxe.NativeStackTrace.exceptionStack();
	}

	public static function origin():Void {
		throw "first";
	}

	public static function secondary():Void {
		throw "second";
	}

	static function main():Void {
		initial = observe();
		if (chooseSecond)
			secondary();
		else
			origin();
	}
}
