/** Implicit inherited reads and writes must use the child's existing receiver. */
class BareReceiver {
	static function main():Void {
		final child = new BareChild(7);
		final base:BareBase = child;
		if (base.value != 8 || child.value != 8)
			throw "implicit inherited access lost the receiver";
	}
}

/** The declaring class owns the slot that the child later updates. */
class BareBase {
	public var value:Int;

	public function new(seed:Int) {
		value = seed;
	}
}

/** The parameter deliberately has another name so value selects the inherited field. */
class BareChild extends BareBase {
	public function new(seed:Int) {
		super(seed);
		value = value + 1;
	}
}
