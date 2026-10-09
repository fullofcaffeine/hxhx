/** Initializer-owned calls preserve concrete receiver types and virtual dispatch. */
class Main {
	public static var held:Box<Payload>;

	static function main():Void {
		final ints = new Reader<Int>();
		final strings = new Reader<String>();
		final bools = new Reader<Bool>();
		if (ints.read(new Box<Int>(7)) != 7 || strings.read(new Box<String>("word")) != "word")
			throw "initializer method call mixed its class arguments";
		if (bools.read(new Box<Bool>(false)) != false || bools.alsoRead(new Box<Bool>(true)) != true)
			throw "initializer method call changed a Boolean result";
		if (ints.read(new IntBox(3)) != 9)
			throw "initializer method call lost a concrete virtual override";
		final inherited = new StringReader();
		if (inherited.read(new Box<String>("inherited")) != "inherited")
			throw "inherited initializer lost its class arguments";
		held = new Box<Payload>(new Payload(9));
		final references = new Reader<Payload>();
		if (references.read(held).number != 9 || references.alsoRead(held).number != 9)
			throw "initializer method call lost its rooted reference result";
	}
}

/** Similar calls in separate fields retain separate lexical owners. */
class Reader<T> {
	public var read:Box<T>->T = function(box:Box<T>):T return box.read();
	public var alsoRead:Box<T>->T = function(box:Box<T>):T return box.read();

	public function new() {}
}

/** An inherited field still belongs to the applied ancestor that declares it. */
class StringReader extends Reader<String> {}

/** Ordinary method semantics remain owned by the selected receiver class. */
class Box<T> {
	public var value:T;

	public function new(value:T)
		this.value = value;

	public function read():T
		return value;
}

/** Dispatch from the generic field closure must reach this concrete override. */
class IntBox extends Box<Int> {
	public override function read():Int
		return 9;
}

/** The independent observer verifies that the generic field retains this object. */
class Payload {
	public var number:Int;

	public function new(number:Int)
		this.number = number;
}
