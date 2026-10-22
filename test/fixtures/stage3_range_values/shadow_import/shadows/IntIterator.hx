package shadows;

/** A user's same-named class must keep its own ordinary constructor identity. */
class IntIterator {
	final state:String;

	public function new() {
		state = "authored";
	}

	public function label():String
		return state;
}
