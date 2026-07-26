/** Exact Bool call boundary used by the portable call-plan contract. */
class BoolCalls {
	public static function negate(value:Bool):Bool {
		Sys.println("bool-callee");
		return !value;
	}
}
