/** Module functions remain distinct from ordinary methods in the same module. */
function record(effects:Array<Int>, digit:Int, value:Bool):Bool {
	effects.push(digit);
	return value;
}

function chosen():Bool
	return false;

private function hidden():Bool
	return true;

/** A real primary class must not make its static methods bare module imports. */
class Functions {
	public static function classValue():Bool
		return true;
}
