/**
	Provides one real typed function body for syntax-handoff lifecycle checks.
**/
class SyntaxInputFixture {
	public function new() {}

	/** Keeps the fixture body small while still depending on a typed argument. */
	public function calculate(value:Int):Int {
		return value + 1;
	}
}
