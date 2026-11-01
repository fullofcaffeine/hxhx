using StringTools;

/**
	Calls `StringTools.replace` with single, multiple, overlapping, empty, and
	missing matches, through both the static call form and the `using` form.
	Each argument comes from a call that logs its position, so the output also
	shows that every argument runs once, left to right.
**/
class Main {
	static var log:Array<String> = [];

	static function arg(label:String, value:String):String {
		log.push(label);
		return value;
	}

	static function main():Void {
		Sys.println("single " + StringTools.replace("hello", "l", "L"));
		Sys.println("multiple " + StringTools.replace("a,b,c,d", ",", ";"));
		Sys.println("overlapping " + StringTools.replace("aaaa", "aa", "b"));
		Sys.println("overlapping3 " + StringTools.replace("aaaaa", "aa", "<>"));
		Sys.println("missing " + StringTools.replace("hello", "z", "Z"));
		Sys.println("empty-by " + StringTools.replace("banana", "a", ""));
		Sys.println("empty-input [" + StringTools.replace("", "a", "b") + "]");
		Sys.println("empty-sub " + StringTools.replace("abc", "", "-"));
		Sys.println("whole " + StringTools.replace("abc", "abc", "xyz"));
		Sys.println("longer " + StringTools.replace("a.b", ".", "::"));
		final text = "one two one";
		Sys.println("using " + text.replace("one", "1"));
		Sys.println("using-chain " + "x-y-z".replace("-", "+").replace("+", "/"));
		final result = StringTools.replace(arg("s", "a-b"), arg("sub", "-"), arg("by", "="));
		Sys.println("order " + result + " " + log.join(","));
		Sys.println("length " + StringTools.replace("ab", "b", "bbb").length);
	}
}
