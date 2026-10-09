import Main.Alpha;
import Main.Beta;
import Main.Unused;

/** Observe the same fields after upstream startup and one authored main invocation. */
class OracleMain {
	static function main():Void {
		Main.main();
		Sys.println(Main.log);
		Sys.println(Alpha.first);
		Sys.println(Alpha.second);
		Sys.println(Beta.value);
		Sys.println(Unused.value);
		Sys.println(Main.wrapA);
		Sys.println(Main.wrapB);
		Sys.println(Main.wrapC);
	}
}
