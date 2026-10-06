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
