/** Exercises planned character encoding through generated and compiled OCaml. */
class Main {
	static var calls = 0;
	static var standaloneCode = 69;
	static final standalone = String.fromCharCode(standaloneCode);

	/** Returns one character code and records how often the argument is evaluated. */
	static function next():Int {
		calls++;
		return 67;
	}

	static function main():Void {
		final zero = String.fromCharCode(0);
		final byte = String.fromCharCode(255);
		final encode:Int->String = String.fromCharCode;
		final nullable:Null<Int> = null;
		var nestedCode = 68;
		final nested = () -> String.fromCharCode(nestedCode);

		Sys.println("zero=" + zero.length + ":" + zero.charCodeAt(0));
		Sys.println("byte=" + byte.length + ":" + byte.charCodeAt(0));
		Sys.println("negative=" + String.fromCharCode(-1).length);
		Sys.println("overflow=" + String.fromCharCode(256).length);
		Sys.println("side=" + String.fromCharCode(next()));
		Sys.println("calls=" + calls);
		Sys.println("value=" + encode(66));
		final nullableResult = String.fromCharCode(nullable);
		Sys.println("nullable=" + nullableResult.length + ":" + nullableResult.charCodeAt(0));
		Sys.println("nested=" + nested());
		Sys.println("standalone=" + standalone);
	}
}
