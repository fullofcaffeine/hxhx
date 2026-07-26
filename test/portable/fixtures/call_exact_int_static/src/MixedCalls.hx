/** Mixed-signature call target used to prove the sealed representation matrix. */
class MixedCalls {
	public static function choose(count:Int, enabled:Null<Bool>):Null<Int> {
		Sys.println("mixed-callee");
		return enabled ? count : null;
	}

	public static function chooseMany(prefix:Int, enabled:Null<Bool>, invert:Bool, fallback:Null<Int>):Null<Int> {
		Sys.println("mixed-many-callee");
		return enabled == invert ? prefix : fallback;
	}
}
