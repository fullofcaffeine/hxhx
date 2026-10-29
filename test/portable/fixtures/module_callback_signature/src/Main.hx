/** Callback exports preserve closure state, arity, optional values and exceptions. */
class Main {
	static function main():Void {
		var prefix = "old";
		var calls = 0;
		final callback = (value:Int) -> {
			calls++;
			return prefix + Std.string(value);
		};
		Sys.println(First.run(callback, 2));
		prefix = "new";
		Sys.println(First.run(callback, 3));
		Sys.println(calls);
		Sys.println(First.empty(() -> "unit"));
		final returned = First.retain(callback);
		Sys.println(returned(4));
		Sys.println(calls);
		Sys.println(First.pair((number:Int, text:String) -> text + Std.string(number)));
		Sys.println(First.optional(function(?value:String):String {
			return value == null ? "omitted" : value;
		}));
		var caught = false;
		try {
			First.run(function(_:Int):String {
				throw "callback failure";
			}, 1);
		} catch (_:Dynamic) {
			// The deliberate thrown value stays inside this test's observation boundary.
			caught = true;
		}
		Sys.println(caught);
	}
}
