/** Proves that default and no-inline builds use one Haxe-authored URL codec. */
class Main {
	static var calls = 0;
	static var standaloneSeed = "standalone value";
	static final standalone = StringTools.urlEncode(standaloneSeed);

	static function once(value:String):String {
		calls++;
		return value;
	}

	static function nested():String {
		return StringTools.urlDecode("nested%20value");
	}

	static function main():Void {
		Sys.println("encode ordinary=" + StringTools.urlEncode("a b"));
		Sys.println("encode reserved=" + StringTools.urlEncode("a/b+c?d=e&f"));
		Sys.println("encode unicode=" + StringTools.urlEncode("café ✓"));
		Sys.println("decode ordinary=" + StringTools.urlDecode("a%20b"));
		Sys.println("decode reserved=" + StringTools.urlDecode("a%2Fb%2Bc%3Fd%3De%26f"));
		Sys.println("decode unicode=" + StringTools.urlDecode("caf%C3%A9%20%E2%9C%93"));
		Sys.println("decode plus=" + StringTools.urlDecode("a+b"));
		Sys.println("decode malformed short=" + StringTools.urlDecode("a%2"));
		Sys.println("decode malformed hex=" + StringTools.urlDecode("a%ZZb"));
		Sys.println("decode malformed end=" + StringTools.urlDecode("a%"));
		Sys.println("decode malformed high=" + StringTools.urlDecode("a%G1b"));
		Sys.println("decode malformed low=" + StringTools.urlDecode("a%1Gb"));
		Sys.println("decode doubled percent=" + StringTools.urlDecode("a%%20b"));
		Sys.println("encode once=" + StringTools.urlEncode(once("side effect value")));
		Sys.println("decode once=" + StringTools.urlDecode(once("side%20effect%20value")));
		Sys.println("calls=" + calls);
		Sys.println("nested=" + nested());
		Sys.println("standalone=" + standalone);
	}
}
