/** Ordinary virtual calls preserve the allocated class after upcast and evaluate operands once. */
class Main {
	static var order:Int = 0;

	static function receiver(value:Base):Base {
		order = order * 10 + 1;
		return value;
	}

	static function argument():Int {
		final temporary = new Base(500);
		order = order * 10 + 2;
		return 3 + temporary.value - 500;
	}

	/** The call itself must keep a temporary receiver alive while its argument allocates. */
	static function collectingReceiver():Void {
		order = 0;
		if (receiver(new Child(19)).read(argument()) != 122 || order != 12)
			throw "collecting argument lost its temporary receiver";
	}

	static function main():Void {
		final plain = new Base(5);
		if (plain.read(2) != 7)
			throw "ordinary instance method returned the wrong value";
		final child = new Child(7);
		final base:Base = child;
		if (child.read(1) != 108 || base.read(2) != 109)
			throw "upcast lost the allocated override";
		if (base.inherited(4) != 111)
			throw "inherited method lost virtual this dispatch";
		if (receiver(base).read(argument()) != 110 || order != 12)
			throw "instance operands changed order or ran more than once";
		base.value = 11;
		if (child.read(0) != 111 || plain.read(0) != 5)
			throw "instance dispatch changed receiver identity";
		final sibling:Base = new Sibling(13);
		if (sibling.read(1) != 214 || base.read(0) != 111)
			throw "sibling dispatch selected another allocated class";
		if (base.spawn().read(1) != 318)
			throw "override allocation was missing from reachable dispatch";
		collectingReceiver();
	}
}

/** A caller inside the base class must still select the receiver's most-derived override. */
class Base {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function read(delta:Int):Int {
		return this.value + delta;
	}

	public function inherited(delta:Int):Int {
		return this.read(delta);
	}

	public function spawn():Base {
		return this;
	}
}

/** Explicit super calls select the parent implementation without re-entering this override. */
class Child extends Base {
	public function new(value:Int) {
		super(value);
	}

	override public function read(delta:Int):Int {
		return super.read(delta) + 100;
	}

	override public function spawn():Base {
		return new Grandchild(17);
	}
}

/** This allocation is discovered only after the planner selects Child.spawn. */
class Grandchild extends Child {
	public function new(value:Int) {
		super(value);
	}

	override public function read(delta:Int):Int {
		return super.read(delta) + 200;
	}
}

/** Loading a related class does not authorize an unneeded generic layout or body. */
class Unallocated<T> extends Base {
	public var item:T;

	public function new(value:Int, item:T) {
		super(value);
		this.item = item;
	}

	override public function read(delta:Int):Int {
		return super.read(delta) + 400;
	}
}

/** Distinct sibling allocations must not share a method choice based only on static receiver type. */
class Sibling extends Base {
	public function new(value:Int) {
		super(value);
	}

	override public function read(delta:Int):Int {
		return super.read(delta) + 200;
	}
}
