/** A nested mutable value whose identity must survive exception transport. */
private typedef Detail = {var code:Int;}

/** A recursive type and a self-reference must not trigger recursive transport. */
private typedef Cycle = {
	var code:Int;
	var next:Null<Cycle>;
}

/** Dynamic elements deliberately model arbitrary values at the exception boundary. */
private typedef Payload = {
	final message:String;
	final detail:Detail;
	final ?items:Array<Dynamic>;
}

/** Exercises opaque transport, rather than selecting field operations from a throw. */
class Main {
	static function sendCycle(value:Cycle):Void {
		throw value;
	}

	/** Mutation through the original reference must reach the caught cyclic value. */
	static function observeCycle():Void {
		final value:Cycle = {code: 7, next: null};
		value.next = value;
		try {
			try {
				sendCycle(value);
			} catch (error:Dynamic) {
				throw error;
			}
		} catch (error:Dynamic) {
			Sys.println("cycle:same=" + (error == value));
			Sys.println("cycle:self=" + (error.next == error));
			value.code = 11;
			Sys.println("cycle:mutation=" + error.next.code);
		}
	}

	static function sendPayload(value:Payload):Void {
		throw value;
	}

	static function relay(value:Payload):Void {
		try {
			sendPayload(value);
		} catch (error:Dynamic) {
			// Haxe's exception channel is Dynamic. No conversion may copy this value.
			throw error;
		}
	}

	static function observe(label:String, value:Payload):Void {
		try {
			relay(value);
		} catch (error:Dynamic) {
			Sys.println(label + ":same=" + (error == value));
			Sys.println(label + ":items-present=" + Reflect.hasField(error, "items"));
			Sys.println(label + ":items-null=" + (Reflect.field(error, "items") == null));
			value.detail.code = 9;
			Sys.println(label + ":nested=" + error.detail.code);
			if (value.items != null) {
				Sys.println(label + ":array-same=" + (error.items == value.items));
				Sys.println(label + ":false=" + Std.isOfType(error.items[0], Bool));
				Sys.println(label + ":zero=" + Std.isOfType(error.items[1], Int));
				Sys.println(label + ":null=" + (error.items[2] == null));
				value.items.push("tail");
				Sys.println(label + ":length=" + error.items.length);
			}
		}
	}

	static function main():Void {
		observe("absent", {message: "failure", detail: {code: 7}});
		observe("null", {message: "failure", detail: {code: 7}, items: null});
		observe("array", {message: "failure", detail: {code: 7}, items: [false, 0, null]});
		final empty:Payload = null;
		try {
			sendPayload(empty);
		} catch (error:Dynamic) {
			Sys.println("null-payload=" + (error == null));
		}
		observeCycle();
	}
}
