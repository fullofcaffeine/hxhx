/** Observe whether an escaped constructor closure shares receiver updates with the returned primitive value. */
class Main {
	static function main():Void {
		final before = new Before(4);
		Sys.println("before-result=" + before.read());
		Sys.println("before-escaped=" + Before.readCaptured());
		Before.writeCaptured(9);
		Sys.println("before-result-after-write=" + before.read());
		Sys.println("before-escaped-after-write=" + Before.readCaptured());
		final after = new After(4);
		Sys.println("after-result=" + after.read());
		Sys.println("after-escaped=" + After.readCaptured());
		After.writeCaptured(9);
		Sys.println("after-result-after-write=" + after.read());
		Sys.println("after-escaped-after-write=" + After.readCaptured());
	}
}

/** The read closure exists before assignment, but its first invocation occurs after assignment. */
abstract Before(Int) {
	public static var readCaptured:Void->Int;
	public static var writeCaptured:Int->Void;

	public function new(value:Int) {
		final read = function():Int {
			return this;
		};
		readCaptured = read;
		writeCaptured = function(next:Int):Void {
			this = next;
		};
		this = value;
		Sys.println("before-inner=" + read());
		this = value + 1;
		Sys.println("before-inner-after-write=" + read());
	}

	public function read():Int {
		return this;
	}
}

/** The read closure exists after assignment, then the constructor replaces its receiver value. */
abstract After(Int) {
	public static var readCaptured:Void->Int;
	public static var writeCaptured:Int->Void;

	public function new(value:Int) {
		this = value;
		final read = function():Int {
			return this;
		};
		readCaptured = read;
		writeCaptured = function(next:Int):Void {
			this = next;
		};
		Sys.println("after-inner=" + read());
		this = value + 1;
		Sys.println("after-inner-after-write=" + read());
	}

	public function read():Int {
		return this;
	}
}
