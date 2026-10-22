/** A parameterized dynamic carrier still supplies its exact enclosing generic binder. */
class AbstractDynamicCases {
	static function main():Void {
		final value:Box<String> = {entry: "value"};
		final holder = value.wrap();
		Sys.println("done");
	}
}

/** Dynamic<T> is the intentional dictionary boundary under test, matching typed foreign object fields. */
abstract Box<T>(Dynamic<T>) from Dynamic<T> to Dynamic<T> {
	public function wrap():Holder<T>
		return new Holder(this);
}

/** The selected parameter must retain Box<T>, without erasing its declaration identity. */
class Holder<T> {
	public function new(value:Box<T>) {
		Sys.println("constructed");
	}
}
