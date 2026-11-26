/**
	How a name written in a pattern is read: a constructor, or a capture.

	A qualified name (`Expr.Constant.CInt`) or a name that starts with an upper-case letter names
	a constructor or constant; any other name captures the matched value. `HxParser` applies this
	rule to `case` patterns, and `HxMatchPattern` applies it to the argument of `e.match(...)`, so
	both read the same pattern the same way.
**/
final class HxSwitchPatternName {
	public static function isConstructor(name:String, qualified:Bool):Bool {
		if (qualified)
			return true;
		if (name == null || name.length == 0)
			return false;
		final c = name.charCodeAt(0);
		return c >= "A".code && c <= "Z".code;
	}
}
