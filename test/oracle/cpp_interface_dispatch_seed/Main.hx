/** A call through this contract must reach the original object's implementation. */
interface Readable {
	public function read(add:Int):Int;
}

/** Extending an interface adds a second contract without allocating a wrapper. */
interface Writable extends Readable {
	public function write(value:Int):Void;
}

/** Direct implementation with mutable state shared by all interface views. */
class Counter implements Writable {
	public var value:Int;

	public function new(value:Int)
		this.value = value;

	public function read(add:Int):Int
		return value + add;

	public function write(value:Int):Void
		this.value = value;
}

/** An inherited implementation keeps its base-class field layout. */
class Inherited extends Counter {
	public function new(value:Int)
		super(value);
}

/** Virtual dispatch selects the override through either interface. */
class Doubled extends Counter {
	public function new(value:Int)
		super(value);

	override public function read(add:Int):Int
		return value * 2 + add;
}

/** A separate implementation prevents the test from assuming a common superclass. */
class Constant implements Readable {
	public function new() {}

	public function read(add:Int):Int
		return 40 + add;
}

/** Interface type arguments remain structural along extended-interface edges. */
interface Source<T> {
	public function get():T;
}

interface IntSource extends Source<Int> {}

/** A concrete return type must adapt to the generic interface call's value storage. */
class NumberSource implements IntSource {
	public function new() {}

	public function get():Int
		return 29;
}

/** Generic implementations preserve null and distinguish applied receiver types. */
class Box<T> implements Source<T> {
	final value:T;

	public function new(value:T)
		this.value = value;

	public function get():T
		return value;
}

/** Unrelated loaded classes must not become dispatch candidates by method name. */
class Unrelated {
	public function new() {}

	public function read(add:Int):Int
		return -100;
}

/** Merely loading a valid implementation must not make it reachable. */
class Unused implements Readable {
	public function new() {}

	public function read(add:Int):Int
		return -200;
}

/** Independent assertions shared by upstream Haxe and the managed C++ regression. */
class Main {
	public static var effects:Int = 0;

	static function read(value:Readable):Int
		return value.read(3);

	static function receiver(value:Readable):Readable {
		effects = effects * 10 + 1;
		return value;
	}

	/** The returned object has no surviving owner except the calling expression. */
	static function edgeReceiver(mode:Int):Readable {
		effects = effects * 10 + 1;
		if (mode == 1)
			throw "receiver";
		if (mode == 3)
			return null;
		return new Counter(11);
	}

	static function edgeArgument(mode:Int):Int {
		effects = effects * 10 + 2;
		final allocation = new Counter(7);
		if (mode == 2)
			throw "argument";
		return allocation.value;
	}

	/** Normal execution and independent failure observers share the same authored call. */
	public static function callEdge(mode:Int):Int {
		effects = 0;
		return edgeReceiver(mode).read(edgeArgument(mode));
	}

	static function main():Void {
		final direct = new Counter(5);
		final writable:Writable = direct;
		final readable:Readable = writable;
		if (read(readable) != 8 || readable != direct || writable != direct)
			throw "direct interface view lost behavior or identity";
		writable.write(11);
		if (direct.value != 11 || readable.read(1) != 12)
			throw "interface mutation lost the original object";
		if (read(new Inherited(13)) != 16 || read(new Doubled(17)) != 37 || read(new Constant()) != 43)
			throw "interface dispatch selected the wrong implementation";
		final another:Readable = new Counter(11);
		if (another == readable)
			throw "distinct implementations acquired equal identity";
		final missing:Readable = null;
		if (missing != null || missing == readable)
			throw "null interface identity changed";
		final generic:IntSource = new NumberSource();
		final parent:Source<Int> = generic;
		if (parent.get() != 29 || generic != parent)
			throw "generic interface view lost substitution or identity";
		final boxed:Source<Int> = new Box<Int>(31);
		final empty:Source<Null<Int>> = new Box<Null<Int>>(null);
		final text:Source<String> = new Box<String>("interface");
		if (boxed.get() != 31 || empty.get() != null || text.get() != "interface")
			throw "generic implementation lost its applied storage or null value";
		final unrelated = new Unrelated();
		if (unrelated.read(0) != -100)
			throw "unrelated implementation changed";
		if (callEdge(0) != 18 || effects != 12)
			throw "interface operands lost order, roots, or single evaluation";
		if (!Std.isOfType(readable, Writable)
			|| !Std.isOfType(new Doubled(3), Readable)
			|| !Std.isOfType(generic, Source)
			|| Std.isOfType(unrelated, Readable)
			|| Std.isOfType(missing, Readable)
			|| Std.isOfType(3, Readable))
			throw "standard interface membership changed";
		if (!(readable is Writable) || !(generic is IntSource) || (unrelated is Readable) || (missing is Readable))
			throw "interface type-test syntax changed";
		effects = 0;
		if (!(receiver(readable) is Readable) || effects != 1)
			throw "interface type test repeated or omitted its operand";
	}
}
