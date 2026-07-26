/**
	Proves that result conversion does not silently reuse legacy return control.
**/
class ResultControlRejected {
	public static function choose(enabled:Bool):Null<Bool> {
		if (enabled)
			return true;
		return null;
	}

	static function main():Void {
		Sys.println(choose(true));
	}
}
