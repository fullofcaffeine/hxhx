/** Check source startup observations with upstream Haxe's native C++ target. */
class OracleMain {
	static function main():Void {
		Main.main();
		if (Main.absent != null || Main.alias != Main.empty || Main.empty != Main.Choice.Empty)
			throw "singleton field initialization differs";
		if (Main.atStartup != Main.Choice.Last || Main.atMain != Main.atStartup)
			throw "singleton startup order differs";
		if (Main.other != Main.Other.Empty || Type.enumIndex(Main.empty) != 0 || Type.enumIndex(Main.atMain) != 1)
			throw "singleton identity or constructor order differs";
		Sys.println("CPP_MANAGED_ENUM_SINGLETON_STARTUP:PASS");
	}
}
