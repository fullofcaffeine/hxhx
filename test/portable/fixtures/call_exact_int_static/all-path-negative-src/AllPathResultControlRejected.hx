/**
	Proves that one directional return does not make a mixed return/throw body
	eligible for the first return-only all-path control slice.
**/
class AllPathResultControlRejected {
	public static function choose(enabled:Bool):Null<Int> {
		if (enabled)
			return 1;
		throw "disabled";
	}

	static function main():Void {
		Sys.println(choose(true));
	}
}
