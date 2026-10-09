/** One authored call must keep each invocation's concrete class arguments. */
class Main {
	public static var held:Box<Payload>;

	static function main():Void {
		final ints = new Box<Int>();
		final strings = new Box<String>();
		final bools = new Box<Bool>();
		final absent:Null<Int> = ints.forward();
		final absentBool:Null<Bool> = bools.forward();
		if (absent != null || absentBool != null || strings.forward() != null)
			throw "nested generic call lost null";
		ints.value = 7;
		strings.value = "word";
		bools.value = true;
		if (ints.forward() != 7 || strings.forward() != "word" || !bools.forward())
			throw "nested calls mixed their enclosing applications";
		if (ints.viaClosure() != 7 || strings.viaClosure() != "word")
			throw "nested closure lost its applied receiver";
		final inherited:Box<String> = new Leaf();
		inherited.value = "inherited";
		if (inherited.forward() != "inherited")
			throw "nested inherited call lost its ancestor arguments";
		final specialized:Box<Int> = new IntLeaf();
		if (specialized.forward() != 9)
			throw "nested virtual call lost its concrete override";
		held = new Box<Payload>();
		held.value = new Payload(9);
		if (held.forward().number != 9)
			throw "nested reference result lost its traced payload";
	}
}

/** Generic null storage survives both the nested receiver and argument/result boundaries. */
class Box<T> {
	public var value:T;

	public function new() {}

	public function read():T
		return value;

	public function echo(next:T):T
		return next;

	public function forward():T
		return this.echo(this.read());

	public function viaClosure():T {
		final read = () -> this.read();
		return read();
	}
}

/** Inherited bodies still execute under the declaring ancestor's applied type. */
class Leaf extends Box<String> {}

/** A generic body must dispatch through the concrete allocation's override. */
class IntLeaf extends Box<Int> {
	public override function read():Int
		return 9;
}

/** The native observer checks this payload after forced collection. */
class Payload {
	public var number:Int;

	public function new(number:Int)
		this.number = number;
}
