/** Observe the same initialization through upstream Haxe's native C++ target. */
class OracleMain {
	static function main():Void {
		Main.main();
		if (Main.calls != 1 || Main.value != 7 || Main.mirror != 7)
			throw "abstract initialization changed its evaluation or value";
		Sys.println("CPP_MANAGED_ABSTRACT_INITIALIZER:PASS");
	}
}
