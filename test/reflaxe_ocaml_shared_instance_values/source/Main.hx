/** The unchanged nullable instance-call behavior required by M14CallArgumentControlTest. */
class Sink {
	public function new() {}

	public function put(value:Null<Int>):Int
		return value == null ? 9 : value;
}

/** Both calls must execute through the constructed receiver and preserve nullable arguments. */
class Main {
	static function main():Void {
		final sink = new Sink();
		if (sink.put(true ? 3 : null) != 3 || sink.put(false ? 3 : null) != 9)
			throw "nullable call";
	}
}
