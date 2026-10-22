/** Source declaration order must not change the dependency between function and method. */
function total(amount:Int):Int {
	final state = new LaterState();
	state.add(amount);
	state.add(amount);
	return state.read();
}

private class LaterState {
	var value:Int = 0;

	public function new() {}

	public function add(amount:Int):Void
		value += amount;

	public function read():Int
		return value;
}
