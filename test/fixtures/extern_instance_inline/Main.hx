/** Exercise null receivers, receiver/argument effects, and inherited generic bodies. */
class Main {
	static var events:String = "";
	static var current:Cell<Int>;

	static function receiver():Cell<Int> {
		events += "r";
		return current;
	}

	static function argument():Int {
		events += "a";
		current = new Cell(99);
		return 3;
	}

	static function main():Void {
		var absent:Cell<Int> = null;
		if (absent.read(4) != 4)
			throw "null receiver";
		current = new Cell(7);
		if (receiver().read(argument()) != 7 || events != "ra" || current.value != 99)
			throw "receiver evaluation order";
		if (current.read(0) != 99 || current.implicitRead(0) != 99)
			throw "present receiver";
		final child = new Child("child");
		if (child.read("fallback") != "child")
			throw "inherited owner specialization";
		if (child.ordinary() != "child")
			throw "ordinary call";
		final copied = child.copy();
		if (copied.value != "child")
			throw "generic inline construction";
		if (Defaults.optional() != 17 || Defaults.optional(null) != 17 || Defaults.optional(0) != 0)
			throw "optional argument";
		if (Defaults.defaulted() != 8 || Defaults.defaulted(null) != 8 || Defaults.defaulted(0) != 0)
			throw "default argument";
		if (Defaults.skip(5) != 5 || Defaults.skip("x", 5) != -1)
			throw "optional slot alignment";
		final packet:Packet = "promoted";
		final promoted:String = packet;
		if (promoted != "promoted")
			throw "generic output conversion";
	}
}

/** The method owns null handling; callers must not dereference this before expansion. */
class Cell<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}

	public extern inline function read(fallback:T):T {
		return this == null ? fallback : value;
	}

	public function implicitRead(fallback:T):T {
		return read(fallback);
	}

	public function ordinary():T {
		return value;
	}

	public extern inline function copy():Cell<T> {
		return new Cell<T>(value);
	}
}

/** Inherited inline bodies specialize the parent's binder using the child's exact ancestry. */
class Child extends Cell<String> {}

/** An omitted slot and an explicit null both enter the authored optional/default contract. */
class Defaults {
	public static extern inline function optional(?value:Int):Int
		return value == null ? 17 : value;

	public static extern inline function defaulted(value:Int = 8):Int
		return value;

	public static extern inline function skip(?text:String, value:Int):Int
		return text == null ? value : -1;
}

/** Models an authored unchecked conversion boundary; the test selects only its valid String result. */
abstract Packet(String) from String {
	@:to public extern inline function promote<T>():T
		return cast this;
}
