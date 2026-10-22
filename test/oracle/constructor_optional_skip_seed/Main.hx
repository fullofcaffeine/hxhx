/** A String argument skips an optional Int slot while retaining its authored effect once. */
class Main {
	static var calls:Int = 0;

	static function text():String {
		calls++;
		return "selected";
	}

	static function main():Void {
		final skipped = new Box(text());
		final supplied = new Box(3, "supplied");
		Sys.println(skipped.label);
		Sys.println(supplied.label);
		Sys.println(calls);
	}
}

/** The required label follows an optional numeric input. */
class Box {
	public var label:String;

	public function new(?number:Int, label:String) {
		this.label = label;
	}
}
