/** Independent reference executes ordinary upstream startup before reading its fields. */
class OracleMain {
	static function main():Void {
		Sys.println(Main.first);
		Sys.println(Main.read());
		Sys.println(Main.label());
	}
}
