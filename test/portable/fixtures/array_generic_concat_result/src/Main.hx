/** Checks a generic Array result consumed by concat without repeating its producer. */
class Main {
	static var calls:Int = 0;

	static function produce():Array<String> {
		calls++;
		return ["middle"];
	}

	static function main():Void {
		final result = ["start"].concat(Bridge.isolate(() -> produce())).concat(["end"]);
		Sys.println(result.join(","));
		Sys.println(calls);
		final events:Array<String> = [];
		final left = ["left"];
		final right = ["right"];
		final joined = Bridge.isolate(() -> {
			events.push("receiver");
			return left;
		}).concat(Bridge.isolate(() -> {
			events.push("argument");
			return right;
		}));
		joined[0] = "changed";
		Sys.println(events.join(","));
		Sys.println(left.join(",") + ":" + right.join(",") + ":" + joined.join(","));
	}
}
