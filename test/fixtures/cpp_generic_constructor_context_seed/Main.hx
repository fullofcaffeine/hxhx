/** Constructor calls use the class arguments of their exact function or field owner. */
class Main {
	public static var held:Box<Payload>;

	static function main():Void {
		final ints = new Factory<Int>();
		final strings = new Factory<String>();
		final bools = new Factory<Bool>();
		if (ints.make(7).value != 7 || strings.make("word").value != "word")
			throw "method construction mixed class arguments";
		if (bools.make(false).value != false || bools.build(true).value != true)
			throw "construction changed Boolean storage";
		if (ints.build(8).value != 8 || strings.build("field").value != "field")
			throw "initializer construction mixed class arguments";
		if (ints.viaClosure(4).value != 4 || strings.viaClosure("closure").value != "closure")
			throw "nested closure construction lost its caller";
		if (ints.child(5).value != 5 || strings.child("child").value != "child")
			throw "omitted child constructor lost forwarded class arguments";
		if (ints.derived(6).value != 6 || strings.derived("super").value != "super")
			throw "explicit super constructor lost class arguments";
		final absentInt:Null<Int> = ints.empty().value;
		if (absentInt != null)
			throw "omitted generic Int changed null";
		final absentBool:Null<Bool> = bools.empty().value;
		if (absentBool != null)
			throw "omitted generic Bool changed null";
		final inherited = new StringFactory();
		if (inherited.build("inherited").value != "inherited")
			throw "inherited initializer lost constructor arguments";
		final references = new Factory<Payload>();
		held = references.build(new Payload(9));
		if (held.value.number != 9 || references.make(new Payload(11)).value.number != 11)
			throw "construction lost a rooted reference";
	}
}

/** Methods and initialized closures are distinct lexical construction owners. */
class Factory<T> {
	public var build:T->Box<T> = function(value:T):Box<T> return new Box<T>(value);
	public var alsoBuild:T->Box<T> = function(value:T):Box<T> return new Box<T>(value);

	public function new() {}

	public function make(value:T):Box<T>
		return new Box<T>(value);

	public function viaClosure(value:T):Box<T> {
		final create = function(item:T):Box<T> return new Box<T>(item);
		return create(value);
	}

	public function child(value:T):Child<T>
		return new Child<T>(value);

	public function derived(value:T):Derived<T>
		return new Derived<T>(value);

	public function empty():Box<T>
		return new Box<T>();
}

/** Omitted construction must still apply the ancestor's field initializers. */
class StringFactory extends Factory<String> {}

/** Optional generic arguments preserve null in primitive applications. */
class Box<T> {
	public var value:T;

	public function new(?value:T)
		this.value = value;
}

/** An absent constructor forwards to the exact applied ancestor. */
class Child<T> extends Box<T> {}

/** A written parent call must use the already allocated child receiver. */
class Derived<T> extends Box<T> {
	public function new(value:T)
		super(value);
}

/** The independent observer checks this reference after forced collection. */
class Payload {
	public var number:Int;

	public function new(number:Int)
		this.number = number;
}
