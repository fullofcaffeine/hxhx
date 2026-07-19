/** Shared event log used by the place-evaluation oracle fixture. */
class EventLog {
	static var events:Array<String> = [];

	public static function reset():Void {
		events = [];
	}

	public static function record(event:String):Void {
		events.push(event);
	}

	public static function render():String {
		return events.join(",");
	}
}
