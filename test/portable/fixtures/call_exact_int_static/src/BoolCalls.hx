/** Exact Bool call boundary used by the portable call-plan contract. */
class BoolCalls {
	public static function negate(value:Bool):Bool {
		Sys.println("bool-callee");
		return !value;
	}

	public static function identityNullable(value:Null<Bool>):Null<Bool> {
		Sys.println("nullable-bool-callee");
		return value;
	}
}
