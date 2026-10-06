/** Two abstract inputs must agree on one constructor's inferred argument. */
class AbstractConflictingInputs {
	static function main():Void {
		final strings:Array<String> = ["value"];
		final integers:Array<Int> = [1];
		final holder = new Holder(strings, integers);
	}
}

abstract Box<T>(Array<T>) from Array<T> {}

class Holder<T> {
	public function new(first:Box<T>, second:Box<T>) {}
}
