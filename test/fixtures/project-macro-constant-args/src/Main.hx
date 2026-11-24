class Main {
	static function main():Void {
		Sys.println(Values.describe("text", 7, 2.5, true));
		// A parenthesized constant, a folded negative Int, and an Int constant for a Float parameter.
		Sys.println(Values.describe(("paren"), -3, 4, false));
		// A hexadecimal Int and a negative Float.
		Sys.println(Values.describe("hex", 0x10, -0.5, true));
		Sys.println(Values.shout("inferred"));
	}
}
