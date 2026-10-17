/** Verifies integer text and argument effects through the native target. */
class Main {
	static var calls:Int = 0;

	static function show(value:haxe.Int32):String {
		return Std.string(value);
	}

	static function next():haxe.Int32 {
		calls++;
		return 7;
	}

	/** Keep both halves behind a returned Int64 carrier, as compiler callers do. */
	static function makeBits():haxe.Int64 {
		return haxe.Int64.make(1, -1);
	}

	static function main():Void {
		final bits = makeBits();
		Sys.println("plain=" + show(1));
		Sys.println("negative=" + show(-1));
		Sys.println("high=" + Std.string(bits.high));
		Sys.println("low=" + Std.string(bits.low));
		Sys.println("call=" + Std.string(next()));
		Sys.println("calls=" + calls);
	}
}
