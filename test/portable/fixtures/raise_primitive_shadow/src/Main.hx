/** A user function named raise must not intercept catch or loop-control primitives. **/
class Main {
	static function raise(value:String):Void {
		Sys.println("user=" + value);
	}

	static function throwValue():Void {
		throw "boom";
	}

	static function main():Void {
		raise("ordinary");
		try {
			throwValue();
		} catch (value:String) {
			Sys.println("caught=" + value);
		}
		var step = 0;
		var total = 0;
		while (step < 4) {
			step++;
			try {
				if (step == 2)
					continue;
				if (step == 4)
					break;
				total += step;
			} catch (value:String) {
				Sys.println("unexpected=" + value);
			}
		}
		Sys.println("total=" + total);
	}
}
