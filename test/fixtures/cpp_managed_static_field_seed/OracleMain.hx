/** Independent source-level observation; the native harness adds forced collection and failures. */
class OracleMain {
	static function main():Void {
		Main.seed(2);
		Sys.println(Main.read());
		final escaped = Main.escaped();
		Main.seed(8);
		Sys.println(escaped());
		Sys.println(Main.update(function():Int {
			return 11;
		}));
		Sys.println(Main.read());
		Sys.println(Main.shadow(6));
	}
}
