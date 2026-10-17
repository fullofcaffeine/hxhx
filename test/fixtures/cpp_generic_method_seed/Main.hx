/** Generic methods retain null in T parameters, locals, and results until a concrete destination converts it. */
class Main {
	public static var held:Box<Payload>;

	static function main():Void {
		final ints = new Box<Int>();
		final strings = new Box<String>();
		final bools = new Box<Bool>();
		final absent:Null<Int> = ints.read();
		if (absent != null)
			throw "generic method lost null";
		final concrete:Int = ints.read();
		if (concrete != 0)
			throw "concrete method result did not convert null";
		ints.write(ints.read());
		final roundtrip:Null<Int> = ints.echo(ints.read());
		if (roundtrip != null)
			throw "generic parameter or local lost null";
		final absentBool:Null<Bool> = bools.read();
		if (absentBool != null)
			throw "generic Boolean method lost null";
		bools.write(true);
		if (!bools.read())
			throw "generic Boolean write was lost";
		ints.write(7);
		strings.write("word");
		if (ints.read() != 7 || strings.read() != "word")
			throw "generic applications interfered";
		final leaf = new Leaf();
		leaf.write("inherited");
		if (leaf.read() != "inherited")
			throw "inherited generic method lost its owner arguments";
		final base:Box<String> = leaf;
		base.write("shared");
		if (leaf.read() != "shared" || base.read() != "shared")
			throw "generic upcast lost its applied ancestor or instance identity";
		final specialized:Box<Int> = new IntLeaf();
		final empty = new Box<Int>();
		specialized.write(empty.read());
		if (specialized.value != 0 || specialized.read() != 9)
			throw "concrete override lost scalar argument conversion or direct result";
		if (specialized.choose(empty.read()) != 4 || specialized.choose(7, 5) != 12 || ints.choose(1) != 4)
			throw "generic override changed omitted or supplied optional arguments";
		final specializedBool:Box<Bool> = new BoolLeaf();
		final emptyBool = new Box<Bool>();
		specializedBool.write(emptyBool.read());
		if (specializedBool.value != false || !specializedBool.read())
			throw "concrete Boolean override lost argument conversion or direct result";
		final concreteBase:IntBase = new GenericIntLeaf<Int>();
		if (concreteBase.read() != 0)
			throw "generic override lost null-to-zero conversion at the concrete result boundary";
		held = new Box<Payload>();
		held.write(new Payload(9));
		final garbage = new Payload(1);
		if (held.read().number != 9 || garbage.number != 1)
			throw "generic method lost a traced result";
	}
}

/** Each application shares class identity but uses its exact argument and result contract. */
class Box<T> {
	public var value:T;

	public function new() {}

	public function read():T
		return value;

	public function write(next:T):Void
		value = next;

	public function choose(next:T, fallback:Int = 4):Int
		return fallback;

	public function echo(next:T):T {
		final retained:T = next;
		return retained;
	}
}

/** The intermediate class forwards its binder to the method's declaring ancestor. */
class Middle<T> extends Box<T> {}

/** A concrete leaf exercises both generic ancestor edges without redeclaring methods. */
class Leaf extends Middle<String> {}

/** Concrete methods use native scalar parameters and results behind a generic base view. */
class IntLeaf extends Box<Int> {
	public override function read():Int
		return 9;

	public override function write(next:Int):Void
		value = next;

	public override function choose(next:Int, fallback:Int = 4):Int
		return next + fallback;
}

/** Null at the generic call boundary becomes false in the concrete override parameter. */
class BoolLeaf extends Box<Bool> {
	public override function read():Bool
		return true;

	public override function write(next:Bool):Void
		value = next;
}

/** A concrete base contract selects a direct Int result at its caller. */
class IntBase {
	public function new() {}

	public function read():Int
		return 9;
}

/** The applied override keeps declared T storage nullable until the concrete caller receives it. */
class GenericIntLeaf<T:Int> extends IntBase {
	public var value:T;

	public override function read():T
		return value;
}

/** A managed reference must survive collection between method argument and result effects. */
class Payload {
	public var number:Int;

	public function new(number:Int)
		this.number = number;
}
