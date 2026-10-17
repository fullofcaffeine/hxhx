/** Iterable callbacks and field initializers must keep their own capture owners. */
class Main {
	static var calls:Int = 0;

	static function acquire(make:Void->Cursor):Cursor
		return make();

	static function main():Void {
		final limit = 2;
		var sum = 0;
		for (key => value in acquire(function():Cursor {
			calls++;
			return new Cursor(limit);
		}))
			sum += key + value;
		if (sum != 11 || calls != 1)
			throw "iterable callback capture or evaluation count";
		final first = new Holder();
		final second = new Holder();
		if (first.readers[0]() != 4 || first.readers[1]() != 6 || second.readers[0]() != 4)
			throw "initializer iteration capture ownership";
	}
}

/** A direct cursor avoids any provider-specific iterator representation. */
class Cursor {
	final limit:Int;
	var index:Int = 0;

	public function new(limit:Int)
		this.limit = limit;

	public function hasNext():Bool
		return index < limit;

	public function next():{key:Int, value:Int} {
		final key = index++;
		return {key: key, value: key * 10};
	}
}

/** Every construction creates fresh callbacks from an authored field initializer. */
class Holder {
	public var readers:Array<Void->Int> = [
		for (key => value in [4, 5])
			function():Int {
				return key + value;
			}
	];

	public function new() {}
}
