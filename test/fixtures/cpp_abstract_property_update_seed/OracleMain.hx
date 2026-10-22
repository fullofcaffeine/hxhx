/** Upstream evaluates the same source; the native observer reads its stored results independently. */
class OracleMain {
	static function main():Void {
		Main.main();
		Sys.println(Main.decrementPostfix);
		Sys.println(Main.decrementPrefix);
		Sys.println(Main.getterCalls);
		Sys.println(Main.incrementPostfix);
		Sys.println(Main.incrementPrefix);
		Sys.println(Main.receiverCalls);
		Sys.println(Main.setterCalls);
		Sys.println(Main.stored);
	}
}
