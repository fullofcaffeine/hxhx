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
		Sys.println(StringTools.isEof(fast("", 0)));
		Sys.println(StringTools.isEof(fast("AZ", 2)));
		Sys.println("".charCodeAt(0) == null);
		Sys.println(text().charCodeAt(index()));
		Sys.println(StringTools.fastCodeAt(text(), index()));
		Sys.println(StringTools.winMetaCharacters.join(","));
		final alias = StringTools.winMetaCharacters;
		alias[0] = 99;
		Sys.println(StringTools.winMetaCharacters[0]);
		alias[0] = 32;
	}
}
