/** The module's primary type has no runtime representation. */
typedef Mixed = Int;

/** A secondary declaration still owns executable behavior. */
class Helper {
	public static function value():Int {
		Sys.println("helper");
		return 7;
	}
}
