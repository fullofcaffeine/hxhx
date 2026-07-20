/** Minimal program whose update receives a sealed place plan before the test mutates its body. */
class Main {
	static function main():Void {
		final counter = new LateMutationCounter();
		counter.increment();
	}
}

private class LateMutationCounter {
	public var value:Int = 0;

	public function new() {}

	public function increment():Void {
		value++;
	}
}
