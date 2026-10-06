/** Independently check which operand effects remain when comparison evaluation throws. */
class FailureOracle {
	static function observe(left:Bool, right:Bool, expected:String, effects:Int):Void {
		var caught = false;
		try {
			Main.compareFailure(left, right);
		} catch (value:String) {
			if (value != expected || Main.effects != effects)
				throw "comparison changed the throw or operand effects";
			caught = true;
		}
		if (!caught)
			throw "comparison did not throw";
	}

	static function main():Void {
		observe(true, false, "left", 1);
		observe(false, true, "right", 12);
	}
}
