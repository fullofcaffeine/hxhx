/** Read the same source effects through upstream Haxe. */
class OracleMain {
	static function main():Void {
		Main.main();
		Sys.println(Main.plain);
		Sys.println(Main.converted);
		Sys.println(Main.calls);
		Sys.println(Main.result);
	}
}
