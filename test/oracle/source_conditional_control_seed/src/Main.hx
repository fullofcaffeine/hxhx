/** A selected value block can throw without evaluating the other branch. */
class Main {
	static function pick(flag:Bool, value:Int):String {
		final result = if (flag) {
			"left";
		} else {
			if (value < 0)
				throw "bad";
			"right";
		}
		return result;
	}

	static function main():Void {
		Sys.println(pick(true, -1));
		Sys.println(pick(false, 0));
		try {
			Sys.println(pick(false, -1));
		} catch (error:String) {
			Sys.println(error);
		}
		final choose = function(flag:Bool):String {
			if (flag) {
				return "closure";
			}
			throw "closed";
		};
		Sys.println(choose(true));
		try {
			Sys.println(choose(false));
		} catch (error:String) {
			Sys.println(error);
		}
	}
}
