/** Proves that a standalone update survives the complete Reflaxe preprocessor lifecycle. */
class Main {
	static function main():Void {
		final counter = new Counter(3);
		final before = counter.value;
		counter.increment();
		Sys.println("before=" + before + " after=" + counter.value);
	}
}

/** Mutable record-backed value whose update is a standalone block element. */
class Counter {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function increment():Void {
		value++;
	}
}
