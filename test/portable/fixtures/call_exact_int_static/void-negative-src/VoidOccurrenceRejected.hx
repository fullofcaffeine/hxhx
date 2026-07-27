/**
	Proves that an admitted Void call cannot fall back to unplanned syntax when
	its static-initializer source context has no sealed function occurrence.
**/
class VoidOccurrenceRejected {
	static final value = {
		VoidRejectedCalls.run();
		1;
	};

	static function main():Void {
		Sys.println(value);
	}
}

class VoidRejectedCalls {
	public static function run():Void {
		Sys.println("must not reach target syntax");
	}
}
