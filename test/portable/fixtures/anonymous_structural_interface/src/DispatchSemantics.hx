/** Parent-interface methods must remain available through a child contract. */
private interface Reading {
	function read():Int;
}

/** Two methods whose implementations have different concrete record positions. */
private interface Changing extends Reading {
	function add(amount:Int):Int;
}

/** The same consumer accepts a class instance or an ordinary anonymous object. */
private typedef MethodView = {
	function read():Int;
	function add(amount:Int):Int;
}

/** Stored fields intentionally precede methods in the concrete class layout. */
private class StoredCounter implements Changing {
	public var value:Int;
	public var padding:String;

	public function new(value:Int) {
		this.value = value;
		padding = "base";
		// Allocation must install dispatch before any user constructor effects.
		final contract:Reading = this;
		if (contract.read() != value)
			throw "constructor interface call";
	}

	public function read():Int {
		return value;
	}

	public function add(amount:Int):Int {
		value += amount;
		return value;
	}
}

/** Overrides retain their owning receiver, including inherited mutable storage. */
private class DerivedCounter extends StoredCounter {
	public var extra:String;

	public function new(value:Int) {
		super(value);
		extra = "derived";
	}

	override public function add(amount:Int):Int {
		value += amount * 2;
		return value;
	}
}

/**
	Checks identity, override selection, capture timing, and allocation ordering.
	Assertions stay silent so the original fixture's output contract is unchanged.
**/
class DispatchSemantics {
	static final initialized:Changing = new DerivedCounter(4);
	static final initializedRead:Int = initialized.read();
	static var selections:Int = 0;

	static function select(value:Changing):Changing {
		selections++;
		return value;
	}

	static function useView(value:MethodView):Int {
		value.add(3);
		return value.read();
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	public static function check():Void {
		require(initializedRead == 4, "interface call during static initialization");
		final instance = new DerivedCounter(10);
		final contract:Changing = instance;
		final parent:Reading = contract;
		require(parent.read() == 10, "parent interface method");
		require(contract.add(2) == 14, "derived override");
		final captured = select(contract).add;
		require(selections == 1, "receiver must be evaluated when capturing");
		require(captured(2) == 18, "captured override");
		require(captured(1) == 20 && selections == 1, "capture must retain its receiver");
		final view:MethodView = contract;
		require(view == instance, "structural conversion must retain identity");
		require(Type.getClass(view) == DerivedCounter, "structural class identity");
		require(Std.downcast(view, DerivedCounter) == instance, "structural downcast identity");
		require(useView(view) == 26, "class-backed structural consumer");
		var anonymousValue = 30;
		final literal:MethodView = {
			read: () -> anonymousValue,
			add: amount -> {
				anonymousValue += amount;
				return anonymousValue;
			}
		};
		require(useView(literal) == 33, "ordinary anonymous consumer");
		require(Type.getClass(literal) == null, "anonymous literal has no class");
		final empty = Type.createEmptyInstance(DerivedCounter);
		empty.value = 7;
		final emptyContract:Changing = empty;
		require(emptyContract.read() == 7, "empty allocation dispatch");
		require(emptyContract.add(2) == 11, "empty allocation override");
	}
}
