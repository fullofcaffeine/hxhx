/** Observe the same integer and effect counter with upstream Haxe. */
class OracleMain {
	static function main():Void {
		Main.main();
		Sys.println(Main.result);
		Sys.println(Main.calls);
		Sys.println(Main.minimum);
		Sys.println(Main.maximum);
		Sys.println(Main.zero);
		Sys.println(Main.negativeOne);
		Sys.println(Main.inverted);
	}
}
