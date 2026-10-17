/** Escaping callbacks share writes within an iteration and keep separate iteration storage. */
class Main {
	static function main():Void {
		final readers:Array<Void->Int> = [];
		final writers:Array<Void->Void> = [];
		for (key => value in [1, 2, 3]) {
			readers.push(function():Int {
				return key + value;
			});
			writers.push(function():Void {
				value += 100;
			});
			value = 10;
		}
		if (readers[0]() != 10 || readers[1]() != 11 || readers[2]() != 12)
			throw "mutation after capture";
		writers[0]();
		if (readers[0]() != 110 || readers[1]() != 11 || readers[2]() != 12)
			throw "shared storage within one iteration";
		final ranges:Array<Void->Int> = [];
		for (index in 0...3)
			ranges.push(function():Int {
				return index;
			});
		if (ranges[0]() != 0 || ranges[1]() != 1 || ranges[2]() != 2)
			throw "range iteration capture";
		final elements:Array<Void->Int> = [];
		for (element in [4, 5, 6])
			elements.push(function():Int {
				return element;
			});
		if (elements[0]() != 4 || elements[1]() != 5 || elements[2]() != 6)
			throw "array element capture";
		final holder = new Holder(7);
		final forwarded = holder.collect();
		if (forwarded[0]()() != 8 || forwarded[1]()() != 10)
			throw "forwarded iteration capture or receiver";
		capturedDeclarations();
	}

	/** Declaration events must stay fresh, share writes, and support recursive initialization. */
	static function capturedDeclarations():Void {
		final readers:Array<Void->Int> = [];
		final writers:Array<Void->Void> = [];
		final recursions:Array<Int->Int> = [];
		for (index in 0...2) {
			var local:Int;
			local = index;
			readers.push(() -> local);
			writers.push(() -> {
				local += 10;
			});
			local += 1;
			final base = index * 10;
			function recurse(count:Int):Int {
				if (count == 0)
					return base;
				return recurse(count - 1) + 1;
			}
			recursions.push(recurse);
		}
		writers[0]();
		if (readers[0]() != 11 || readers[1]() != 2)
			throw "captured declarations must share only their own execution's writes";
		if (recursions[0](2) != 2 || recursions[1](2) != 12)
			throw "recursive declaration must capture its initialized cell";
	}
}

/** A middle closure forwards loop cells while both callbacks retain the instance receiver. */
class Holder {
	final offset:Int;

	public function new(offset:Int) {
		this.offset = offset;
	}

	public function collect():Array<Void->(Void->Int)> {
		return [
			for (key => value in [1, 2])
				function():Void->Int {
					return function():Int {
						return this.offset + key + value;
					};
				}
		];
	}
}
