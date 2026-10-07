/** Holds state used by module functions in the same source module. */
private class CounterState {
	var value:Int = 0;

	public function new() {}

	public function add(amount:Int):Void
		value += amount;

	public function read():Int
		return value;
}

/** Calls a same-module class method through a module function. */
private function addTwice(state:CounterState, amount:Int):Void {
	state.add(amount);
	state.add(amount);
}

function total(amount:Int):Int {
	final state = new CounterState();
	addTwice(state, amount);
	return state.read();
}
