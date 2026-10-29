/** Observe the authored cast program independently through upstream native C++. */
class OracleMain {
	static function main():Void {
		Main.main();
		if (Main.argumentResult != 7 || Main.calls != 1 || Main.direct != 7 || Main.localResult != 11 || Main.nestedResult != 13 || Main.once != 7
			|| Main.returnResult != 14)
			throw "authored cast changed its result or evaluation count";
		Sys.println("CPP_MANAGED_AUTHORED_CAST:PASS");
	}
}
