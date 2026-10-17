/** Compare a completed constructor's backing value with its exact authored method result. */
class ReceiverValueMain {
	public static var events:String = '';

	static function input():Int {
		events += 'argument;';
		return 7;
	}

	static function main():Void {
		final constructed = new ReceiverValue(input());
		// This explicit cast observes the abstract's Int backing without invoking a method.
		final result:Int = cast constructed;
		Sys.println(result);
		Sys.println(events);
		Sys.println(constructed.read());
	}
}

/** An argument passthrough cannot preserve both writes and the constructor's event sequence. */
abstract ReceiverValue(Int) {
	public function new(value:Int) {
		ReceiverValueMain.events += 'body;';
		this = value * 2;
		this += 1;
		ReceiverValueMain.events += 'assigned;';
	}

	/** Reading through a method must use the same completed backing value as an explicit cast. */
	public function read():Int {
		return this;
	}
}
