/** Instance updates select one receiver and preserve prefix/postfix values across allocating selection. */
class Main {
	static var selections:Int = 0;

	static function select(value:Counter):Counter {
		selections++;
		final temporary = new Counter();
		temporary.value = 99;
		if (temporary.value != 99)
			throw "receiver allocation failed";
		return value;
	}

	static function main():Void {
		final counter = new Counter();
		if (select(counter).value++ != 7 || counter.value != 8 || selections != 1)
			throw "postfix increment changed receiver or result";
		if (++select(counter).value != 9 || counter.value != 9 || selections != 2)
			throw "prefix increment changed receiver or result";
		if (select(counter).value-- != 9 || counter.value != 8 || selections != 3)
			throw "postfix decrement changed receiver or result";
		if (--select(counter).value != 7 || counter.value != 7 || selections != 4)
			throw "prefix decrement changed receiver or result";
		counter.value = 2147483647;
		if (counter.value++ != 2147483647 || counter.value != -2147483648)
			throw "instance increment lost Int wraparound";
		if (--counter.value != 2147483647)
			throw "instance decrement lost Int wraparound";
		counter.value = 0;
		final increment = counter.callback();
		if (increment() != 1 || increment() != 2 || counter.value != 2)
			throw "callback update lost its captured receiver";
	}
}

/** A closure retains this exact receiver while its mutable field is updated. */
class Counter {
	public var value:Int = 7;

	public function new() {}

	public function callback():() -> Int {
		return function():Int return ++value;
	}
}
