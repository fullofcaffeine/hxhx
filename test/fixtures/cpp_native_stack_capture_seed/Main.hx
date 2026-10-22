/** Retain a real NativeStackTrace result after the capturing method returns. */
class Main {
	// Any is the standard stack API's opaque boundary. Only the native observer
	// recovers its checked snapshot layout; ordinary Haxe never inspects its bits.
	public static var saved:Any;

	/** A same-named authored method must never select the native binding. */
	public static function callStack():Any {
		return null;
	}

	static function capture():Any {
		return haxe.NativeStackTrace.callStack();
	}

	static function main():Void {
		saved = capture();
	}
}
