/** Compare portable character codes and EOF detection without assuming a universal sentinel. */
class Main {
	static function text():String {
		Sys.println("text");
		return "AZ";
	}

	static function index():Int {
		Sys.println("index");
		return 1;
	}

	static function main():Void {
		Sys.println(StringTools.fastCodeAt("AZ", 0));
		Sys.println(StringTools.unsafeCodeAt("AZ", 1));
		Sys.println(StringTools.isEof(StringTools.fastCodeAt("", 0)));
		Sys.println(StringTools.isEof(StringTools.fastCodeAt("AZ", 2)));
		Sys.println(StringTools.isEof(StringTools.fastCodeAt("AZ", 0)));
		final fast = StringTools.fastCodeAt;
		final unsafe = StringTools.unsafeCodeAt;
		Sys.println(fast("AZ", 0));
		Sys.println(unsafe("AZ", 1));
		Sys.println(StringTools.fastCodeAt(text(), index()));
	}
}
