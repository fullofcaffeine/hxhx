/** Instance-call control that must remain outside the first static-call family. */
class Counter {
	public function new() {}

	public function increment(value:Int):Int {
		return value + 1;
	}
}
