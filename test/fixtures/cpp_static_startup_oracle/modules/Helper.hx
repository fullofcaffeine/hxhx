/** A module whose startup effect must survive references from nonexecuting source. */
class Helper {
	public static var value:Int = initialize();

	static function initialize():Int {
		Sys.println("helper");
		return 1;
	}

	public static function call():Void {}
}
