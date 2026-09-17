/** Returns a retained enum value after an observable validation step. */
class Reader {
	public function new() {}

	function read():Payload {
		return Text("ok");
	}

	public function parse():Payload {
		Sys.println("before");
		final value = read();
		Sys.println("checked");
		return value;
	}
}
