/** Keeps observable state behind an interface. */
class Counter implements ICounter {
	var value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function add(amount:Int):Int {
		value += amount;
		return value;
	}

	public function read():Int {
		return value;
	}
}
