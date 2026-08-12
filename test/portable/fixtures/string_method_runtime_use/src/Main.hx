/** Exercises planned direct String methods through generated and compiled OCaml. */
class Main {
	static var receiverCalls = 0;
	static var argumentCalls = 0;
	static var order = "";
	static final standalone = "abc".toUpperCase();

	/** Returns a receiver and records when Haxe evaluates it. */
	static function receiver():String {
		receiverCalls++;
		order += "R";
		return "abcabc";
	}

	/** Returns a search value and records when Haxe evaluates it. */
	static function needle():String {
		argumentCalls++;
		order += "A";
		return "bc";
	}

	/** Returns a missing optional index and records when Haxe evaluates it. */
	static function missingIndex():Null<Int> {
		argumentCalls++;
		order += "N";
		return null;
	}

	static function main():Void {
		final text = "abcabc";
		final missing:Null<Int> = null;
		final two:Null<Int> = 2;
		final nested = () -> "abc".substr(1);

		Sys.println("upper=" + text.toUpperCase());
		Sys.println("lower=" + text.toLowerCase());
		Sys.println("char=" + text.charAt(1));
		Sys.println("code=" + text.charCodeAt(1));
		final exactCode:Int = text.charCodeAt(1);
		Sys.println("exactCode=" + exactCode);
		Sys.println("indexOmitted=" + text.indexOf("bc"));
		Sys.println("indexNull=" + text.indexOf("bc", null));
		Sys.println("indexMissing=" + text.indexOf("bc", missing));
		Sys.println("indexTwo=" + text.indexOf("bc", two));
		Sys.println("lastOmitted=" + text.lastIndexOf("bc"));
		Sys.println("lastNull=" + text.lastIndexOf("bc", null));
		Sys.println("lastMissing=" + text.lastIndexOf("bc", missing));
		Sys.println("lastTwo=" + text.lastIndexOf("bc", two));
		Sys.println("split=" + "a,b,".split(",").join("|"));
		Sys.println("substrOmitted=" + text.substr(2));
		Sys.println("substrNull=" + text.substr(2, null));
		Sys.println("substrMissing=" + text.substr(2, missing));
		Sys.println("substrTwo=" + text.substr(2, two));
		Sys.println("substringOmitted=" + text.substring(2));
		Sys.println("substringNull=" + text.substring(2, null));
		Sys.println("substringMissing=" + text.substring(2, missing));
		Sys.println("substringTwo=" + text.substring(2, two));
		Sys.println("toString=" + text.toString());
		Sys.println("nested=" + nested());
		Sys.println("standalone=" + standalone);

		Sys.println("sideResult=" + receiver().lastIndexOf(needle(), missingIndex()));
		Sys.println("sideCalls=" + receiverCalls + ":" + argumentCalls + ":" + order);
	}
}
