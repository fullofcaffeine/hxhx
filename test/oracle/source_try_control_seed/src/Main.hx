/** Try values retain typed catch order and returns from the authored function. */
class Main {
	static function main():Void {
		final choose = function(kind:Int):String {
			return try {
				if (kind == 1)
					throw "problem";
				if (kind == 2)
					throw 7;
				"ok";
			} catch (number:Int) {
				"number:" + number;
			} catch (text:String) {
				"text:" + text;
			};
		};
		Sys.println(choose(0));
		Sys.println(choose(1));
		Sys.println(choose(2));
		var events = "";
		final guarded = function(fail:Bool):String {
			try {
				if (fail)
					throw "bad";
				return "from-try";
			} catch (error:String) {
				return "from-catch";
			}
			events += "after";
			return "wrong";
		};
		Sys.println(guarded(false));
		Sys.println(guarded(true));
		Sys.println(events);
	}
}
