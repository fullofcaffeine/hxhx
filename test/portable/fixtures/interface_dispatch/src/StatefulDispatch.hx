private interface Reading {
	function read():Int;
}

private interface Changing extends Reading {
	function add(amount:Int):Int;
}

/** Different concrete fields must not change the meaning of an interface call. */
private class StoredCounter implements Changing {
	public var padding:String;
	public var value:Int;
	public var initialRead:Int;

	public function new(value:Int) {
		padding = "padding";
		this.value = value;
		final reading:Reading = this;
		initialRead = reading.read();
	}

	public function read():Int
		return value;

	public function add(amount:Int):Int
		return value += amount;
}

private class DerivedCounter extends StoredCounter {
	public var extra:String;

	public function new(value:Int) {
		super(value);
		extra = "derived";
	}

	override public function add(amount:Int):Int
		return value += amount * 2;
}

/**
	Proves original-object state, inherited contracts, and capture timing.
	The assertions are also run with upstream Haxe; stdout stays unchanged.
**/
class StatefulDispatch {
	static var selections:Int = 0;
	static var initialized:Changing = new DerivedCounter(4);
	static var initializedRead:Int = initialized.read();

	static function select(value:Changing):Changing {
		selections++;
		return value;
	}

	static function require(condition:Bool, reason:String):Void {
		if (!condition)
			throw reason;
	}

	public static function check():Void {
		require(initializedRead == 4, "static initializer dispatch");
		final instance = new DerivedCounter(3);
		require(instance.initialRead == 3, "constructor dispatch before return");
		final contract:Changing = instance;
		final parent:Reading = contract;
		require(parent.read() == 3, "parent interface");
		final captured = select(contract).add;
		require(selections == 1, "receiver evaluated at capture");
		require(captured(2) == 7 && captured(1) == 9, "captured override and shared state");
		require(selections == 1 && instance.value == 9 && parent.read() == 9, "receiver reused without copying");
		final nested = function():Int return contract.add(1);
		require(nested() == 11, "nested function interface call");
		require(Type.getClass(contract) == DerivedCounter, "class identity");
		require(Std.downcast(contract, DerivedCounter) == instance, "downcast identity");
		final empty = Type.createEmptyInstance(DerivedCounter);
		empty.value = 7;
		final emptyContract:Changing = empty;
		require(emptyContract.read() == 7 && emptyContract.add(2) == 11, "empty allocation dispatch");
	}
}
