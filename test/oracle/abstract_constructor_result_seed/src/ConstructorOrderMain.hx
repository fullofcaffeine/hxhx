/** Observe argument order and arbitrary constructor statements through one event log. */
class ConstructorOrderMain {
	public static var events:String = "";

	static function input(label:String, value:Int):Int {
		events += label + ";";
		return value;
	}

	static function main():Void {
		final result = new OrderedResult(input("left", 2), input("right", 3));
		Sys.println(result.read());
		Sys.println(events);
	}
}

/** Construction transforms both inputs and records effects around receiver writes. */
abstract OrderedResult(Int) {
	public function new(left:Int, right:Int) {
		ConstructorOrderMain.events += "body;";
		this = left * 10 + right;
		ConstructorOrderMain.events += "assigned;";
		for (index in 0...2) {
			this += 1;
			ConstructorOrderMain.events += "step;";
		}
		ConstructorOrderMain.events += "done;";
	}

	public function read():Int {
		return this;
	}
}
