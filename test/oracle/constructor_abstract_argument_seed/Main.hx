/** An abstract header conversion must remain valid at an ordinary constructor call. */
class Main {
	static function main():Void {
		final box = new Box("hello");
		Sys.println(box.value);
	}
}

/** The declared conversion preserves the underlying String value. */
abstract Label(String) from String to String {}

/** Store the selected abstract parameter without changing its runtime value. */
class Box {
	public var value:Label;

	public function new(value:Label) {
		this.value = value;
	}
}
