/**
	Provides the first callable boundary whose parameter and result use the
	sealed exact `Null<Int>` carrier.
**/
class NullableCalls {
	public static function identity(value:Null<Int>):Null<Int> {
		Sys.println("nullable-callee");
		return value;
	}
}
