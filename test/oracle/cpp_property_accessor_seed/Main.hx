/** Independently authored expectations for stored and virtual Haxe properties. */
class Main {
	static var order:Int;
	static var globalValue:Int;
	static var global(get, set):Int;

	static function get_global():Int {
		return globalValue;
	}

	static function set_global(value:Int):Int {
		globalValue = value;
		return value + 10;
	}

	static function receiver():Base {
		order = order * 10 + 1;
		return new Child(7);
	}

	static function argument():Int {
		order = order * 10 + 2;
		final allocation = new Base(4);
		return allocation.value;
	}

	static function privateRead(value:Stored):Int {
		@:privateAccess return value.hidden;
	}

	static function main():Void {
		final base:Base = new Child(7);
		if (base.value != 107)
			throw "getter override after upcast";
		if ((base.value = 4) != 14)
			throw "assignment must return setter result";
		if (base.value != 104)
			throw "setter must update backing state";
		if (base.readImplicit() != 104)
			throw "implicit getter must retain virtual receiver";
		if (base.readOnly != 4)
			throw "read-only getter";
		if ((base.value += 2) != 116)
			throw "compound assignment must return setter result";
		if (base.readOnly != 106)
			throw "compound assignment must read before write";
		if (++base.value != 217)
			throw "prefix update must return setter result";
		if (base.value++ != 307)
			throw "postfix update must return old getter result";
		if (base.readOnly != 308)
			throw "postfix must write incremented getter result";
		if ((untyped base.value = 12) != 22)
			throw "untyped virtual assignment must return its setter result";
		if (base.readOnly != 12)
			throw "untyped virtual assignment must update authored backing state";

		order = 0;
		if ((receiver().value = argument()) != 14)
			throw "temporary receiver must survive allocating argument";
		if (order != 12)
			throw "receiver and argument must execute once in order";
		order = 0;
		if ((receiver().value += argument()) != 121)
			throw "compound accessor result";
		if (order != 12)
			throw "compound receiver must execute once";

		if ((global = 3) != 13)
			throw "static implicit setter";
		if (Main.global != 3)
			throw "static explicit getter";
		if ((Main.global += 2) != 15)
			throw "static compound setter";

		final stored = new Stored();
		if ((stored.value = 6) != 16)
			throw "isVar setter result";
		if (stored.value != 6)
			throw "isVar accessor must use owned storage";
		if ((stored.mixed = 8) != 18)
			throw "mixed setter result";
		if (stored.mixed != 8)
			throw "default getter must use owned storage";
		// This explicit compatibility boundary exercises Haxe's unchecked access
		// permission. The declared Int type and expected value remain concrete.
		untyped stored.hidden = 9;
		if ((untyped stored.hidden) != 9)
			throw "untyped source must retain restricted stored-field access";
		untyped stored.value = 11;
		if (stored.value != 11)
			throw "untyped property assignment must still invoke its setter";
		checkPrivateAccess(stored, base);
		checkAbstractAccess();
		checkAbstractWriteback();
	}

	/** A setter that replaces this must update the caller's abstract value. */
	static function checkAbstractWriteback():Void {
		var counter = new Counter(3);
		if ((counter.value = 5) != 15 || counter.value != 5)
			throw "abstract setter must replace caller storage and retain its result";
		if ((counter.value += 2) != 17 || counter.value != 7)
			throw "abstract compound setter must replace caller storage";
		if (counter.value++ != 7 || counter.value != 8)
			throw "abstract postfix must retain its old value and replace caller storage";
		if (++counter.value != 19 || counter.value != 9)
			throw "abstract prefix must retain its setter result and replace caller storage";
		if ((counter.added = 2) != 11 || counter.value != 11)
			throw "compound assignment inside a setter must replace caller storage";
		if ((counter.next = 0) != 12 || counter.value != 12)
			throw "unary update inside a setter must replace caller storage";
		final box = new CounterBox();
		order = 0;
		if ((counterReceiver(box).count.value += argument()) != 17 || box.count.value != 7 || order != 12)
			throw "abstract compound setter must retain its field address before the argument";
		order = 0;
		if ((counterReceiver(box).count.value = argument()) != 14 || box.count.value != 4 || order != 211)
			throw "inline setter must preserve authored receiver occurrences after its argument";
	}

	static function counterReceiver(box:CounterBox):CounterBox {
		order = order * 10 + 1;
		return box;
	}

	/** Abstract accessors preserve effects, assignment results, and one receiver evaluation. */
	static function checkAbstractAccess():Void {
		final reading = new Reading(7);
		if (reading.value != 7 || reading.reads != 1)
			throw "abstract getter must execute its authored body";
		if ((reading.value = 9) != 19 || reading.writes != 1)
			throw "abstract assignment must return its setter result";
		if ((reading.value += 2) != 21 || reading.reads != 2 || reading.writes != 2)
			throw "abstract compound access must call getter and setter once";
		if (reading.value++ != 11 || reading.reads != 3 || reading.writes != 3)
			throw "abstract postfix must return the getter result";
		order = 0;
		if ((readingReceiver(reading).value += argument()) != 26 || order != 12)
			throw "abstract receiver and argument must execute once in order";
		if (reading.reads != 4 || reading.writes != 4 || reading.value != 16)
			throw "abstract access must retain the same backing storage";
	}

	static function readingReceiver(value:Reading):Reading {
		order = order * 10 + 1;
		return value;
	}

	/** Check access permission on the same objects after the ordinary property assertions. */
	static function checkPrivateAccess(stored:Stored, base:Base):Void {
		@:privateAccess stored.hidden = stored.hidden + 1;
		@:privateAccess var observed:Int = stored.hidden;
		if (observed != 10 || privateRead(stored) != 10)
			throw "privateAccess assignment and local declaration scope";
		@:privateAccess {
			stored.hidden += stored.hidden;
			if (stored.hidden != 20)
				throw "privateAccess block";
		}
		if ((++ @:privateAccess stored.hidden) != 21)
			throw "privateAccess prefix place";
		if ((@:privateAccess stored.hidden++) != 21)
			throw "privateAccess postfix result";
		if ((@:privateAccess base.value = 13) != 23 || (@:privateAccess base.value) != 113)
			throw "privateAccess must preserve setter results and virtual getters";
	}
}

/** Virtual properties use separate authored storage and may dispatch to an override. */
class Base {
	var stored:Int;

	public var value(get, set):Int;
	public var readOnly(get, never):Int;

	public function new(value:Int) {
		stored = value;
	}

	function get_value():Int {
		return stored;
	}

	function set_value(value:Int):Int {
		stored = value;
		return value + 10;
	}

	function get_readOnly():Int {
		return stored;
	}

	public function readImplicit():Int {
		return value;
	}
}

/** A property read through Base must select this allocated class's getter. */
class Child extends Base {
	public function new(value:Int) {
		super(value);
	}

	override function get_value():Int {
		return super.get_value() + 100;
	}
}

/** Stored properties bypass their accessor only from the matching accessor body. */
class Stored {
	@:isVar public var value(get, set):Int;
	public var mixed(default, set):Int;
	public var hidden(null, default):Int;

	public function new() {}

	function get_value():Int {
		return value;
	}

	function set_value(value:Int):Int {
		this.value = value;
		return value + 10;
	}

	function set_mixed(value:Int):Int {
		mixed = value;
		return value + 10;
	}
}

/** Mutable backing storage makes abstract accessor effects observable. */
class AbstractStorage {
	public var value:Int;
	public var reads:Int = 0;
	public var writes:Int = 0;

	public function new(value:Int) {
		this.value = value;
	}
}

/** User-defined properties select authored methods without a target-specific rule. */
abstract Reading(AbstractStorage) {
	public inline function new(value:Int) {
		this = new AbstractStorage(value);
	}

	public var value(get, set):Int;
	public var reads(get, never):Int;
	public var writes(get, never):Int;

	inline function get_value():Int {
		this.reads++;
		return this.value;
	}

	inline function set_value(value:Int):Int {
		this.writes++;
		this.value = value;
		return value + 10;
	}

	inline function get_reads():Int {
		return this.reads;
	}

	inline function get_writes():Int {
		return this.writes;
	}
}

/** No implicit Int conversion is available outside this abstract's authored methods. */
abstract Counter(Int) {
	public inline function new(value:Int) {
		this = value;
	}

	public var value(get, set):Int;
	public var added(never, set):Int;
	public var next(never, set):Int;

	inline function get_value():Int {
		return this;
	}

	inline function set_value(value:Int):Int {
		this = value;
		return this + 10;
	}

	inline function set_added(value:Int):Int {
		this += value;
		return this;
	}

	inline function set_next(ignored:Int):Int {
		this
		++;
		return this;
	}
}

/** A stored abstract exercises writeback beyond a direct local variable. */
class CounterBox {
	public var count:Counter;

	public function new() {
		count = new Counter(3);
	}
}
