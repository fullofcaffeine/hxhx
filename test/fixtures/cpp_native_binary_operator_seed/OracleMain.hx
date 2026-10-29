/** Read the original program's results through upstream Haxe. */
class OracleMain {
	static function main():Void {
		Main.main();
		Sys.println(Main.less);
		Sys.println(Main.sum);
		Sys.println(Main.mixed);
		Sys.println(Main.compound);
		Sys.println(Main.equal);
		Sys.println(Main.negated);
		Sys.println(Main.effects);
	}
}
