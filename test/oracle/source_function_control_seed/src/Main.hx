/** An inner value group must return from this function before the later event. */
class Main {
	static function main():Void {
		var invoke = function(item:String):Dynamic {
			var result = {
				{
					return item;
				}
				"wrong";
			};
			State.events += "after";
			return result;
		};
		Sys.println(invoke("ok"));
		Sys.println(State.events);
	}
}

/** Keep the runtime observer separate from the entry class's static-storage contract. */
class State {
	public static var events:String = "";
}
