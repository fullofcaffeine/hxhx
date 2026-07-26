/**
	Proves that an admitted optional call cannot fall back to builder-time
	argument padding when its source context has no sealed occurrence plan.
**/
class OptionalOccurrenceRejected {
	static final value = OptionalRejectedCalls.optionalInt();

	static function main():Void {
		Sys.println(value);
	}
}

class OptionalRejectedCalls {
	public static function optionalInt(?value:Int):Int {
		return value == null ? -1 : value;
	}
}
