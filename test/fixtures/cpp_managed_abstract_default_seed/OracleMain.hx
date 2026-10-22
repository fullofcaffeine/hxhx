/** Observe abstract defaults with the upstream native C++ target. */
class OracleMain {
	static function main():Void {
		Main.main();
		if (Main.absent != null || Main.chain != null || Main.seen != null || Main.nullable != null)
			throw "reference or nullable abstract default differs";
		if (Main.number != 0 || Main.flag != false || Main.generic != 0)
			throw "scalar abstract default differs";
		Sys.println("CPP_MANAGED_ABSTRACT_DEFAULT:PASS");
	}
}
