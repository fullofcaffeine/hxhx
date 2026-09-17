/** Observes actual array storage across a call, so scalar replacement cannot hide missing boxes. */
class Main {
	static var calls = 0;

	static function next():Bool {
		calls++;
		return true;
	}

	/** Dynamic is intentional: this boundary must distinguish mixed runtime value types. */
	static function observe(payload:{items:Array<Dynamic>}):Void {
		final values = payload.items;
		Sys.println("false-bool=" + Std.isOfType(values[0], Bool));
		Sys.println("false-not-int=" + !Std.isOfType(values[0], Int));
		Sys.println("zero-int=" + Std.isOfType(values[1], Int));
		Sys.println("null=" + (values[2] == null));
		Sys.println("true-bool=" + Std.isOfType(values[3], Bool));
		Sys.println("one-int=" + Std.isOfType(values[4], Int));
		Sys.println("calls=" + calls);
		values.push("tail");
		Sys.println("alias-length=" + payload.items.length);
	}

	static function main():Void {
		observe({items: [false, 0, null, next(), 1]});
	}
}
