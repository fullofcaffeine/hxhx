/** Upstream alone executes this observer; native code observes the same fields separately. */
class OracleMain {
	static function main():Void {
		Main.main();
		Sys.println(Main.arrayCalls);
		Sys.println(Main.arrayPostfix);
		Sys.println(Main.arrayPrefix);
		Sys.println(Main.arrayStored);
		Sys.println(Main.assignedPostfix);
		Sys.println(Main.assignedResult);
		Sys.println(Main.assignedStored);
		Sys.println(Main.fieldCalls);
		Sys.println(Main.fieldPostfix);
		Sys.println(Main.fieldPrefix);
		Sys.println(Main.fieldStored);
		Sys.println(Main.indexCalls);
		Sys.println(Main.localPostfix);
		Sys.println(Main.localPrefix);
		Sys.println(Main.localStored);
		Sys.println(Main.rhsCalls);
		Sys.println(Main.rhsResult);
		Sys.println(Main.rhsStored);
		Sys.println(Main.shared.get());
	}
}
