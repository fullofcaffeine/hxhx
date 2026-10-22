/** Authored assertions observe sibling sharing and separate initializer invocations. */
class Main {
	static function main():Void {
		final first = new Counter();
		final second = new Counter();
		if (first.callbacks[0](3) != 10 || first.callbacks[1](99) != 10)
			throw "initializer siblings lost shared state";
		if (second.callbacks[1](99) != 7 || second.callbacks[0](2) != 9 || first.callbacks[1](99) != 10)
			throw "initializer invocations shared a cell";
		if (first.objectCallback() != 21 || second.objectCallback() != 21)
			throw "initializer callback lost its captured object";
	}
}

/** Each construction creates a cell that outlives its initializer and is shared by its callbacks. */
class Counter {
	public var callbacks:Array<Int->Int> = {
		var value = 7;
		[
			function(delta:Int):Int {
				var apply:Void->Int = function():Int {
					var result:Int;
					result = value + delta;
					value = result;
					return result;
				};
				return apply();
			},
			function(ignored:Int):Int return value
		];
	};
	public var objectCallback:Void->Int = {
		var held = new Payload(21);
		function():Int {
			new Payload(99);
			return held.value;
		};
	};

	public function new() {}
}

/** A captured managed object must survive allocations performed inside its callback. */
class Payload {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}
