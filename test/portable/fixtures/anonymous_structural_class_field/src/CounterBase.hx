/** Supplies inherited stateful methods for a structural view of a class. */
class CounterBase {
	var count:Int;

	public function new(count:Int) {
		this.count = count;
	}

	public function add(amount:Int):Int {
		count += amount;
		return count;
	}

	public function read():Int {
		return count;
	}
}
