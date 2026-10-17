/** Authored generic initializers preserve null before any later field assignment. */
class Main {
	public static var held:Box<Payload>;

	static function main():Void {
		final ints = new Box<Int>();
		final bools = new Box<Bool>();
		final strings = new Box<String>();
		final absent:Null<Int> = ints.value;
		final absentBool:Null<Bool> = bools.value;
		if (absent != null || absentBool != null || strings.value != null)
			throw "generic initializer lost null";
		final closureAbsent:Null<Int> = ints.exchange(7);
		final closureAbsentBool:Null<Bool> = bools.exchange(false);
		if (closureAbsent != null || closureAbsentBool != null || strings.exchange("one") != null)
			throw "initializer closure lost its null result";
		ints.value = 7;
		bools.value = false;
		strings.value = "word";
		final presentBool:Null<Bool> = bools.value;
		if (ints.value != 7 || presentBool == null || bools.value != false || strings.value != "word")
			throw "initialized applications mixed their stored values";
		if (ints.echo(7) != 7 || bools.echo(false) != false || strings.echo("word") != "word")
			throw "initializer closure mixed generic arguments or results";
		final previousBool:Null<Bool> = bools.exchange(true);
		if (ints.exchange(8) != 7 || previousBool == null || previousBool != false || strings.exchange("two") != "one")
			throw "initializer closure lost its captured generic local";
		final inherited = new Leaf();
		if (inherited.value != null || inherited.marker != 3)
			throw "forwarded constructor lost its generic field initializer";
		inherited.value = "inherited";
		if (inherited.value != "inherited" || inherited.exchange("first") != null || inherited.exchange("second") != "first")
			throw "inherited initialized field lost its concrete type";
		held = new Box<Payload>();
		if (held.value != null)
			throw "reference initializer lost null";
		held.value = new Payload(9);
		if (held.value.number != 9 || held.echo(held.value).number != 9)
			throw "initialized reference field lost its payload";
		if (held.exchange(new Payload(21)) != null || held.exchange(new Payload(22)).number != 21)
			throw "initializer capture lost a reference across allocation";
	}
}

/** The initializer belongs to this field, independently of the constructor body. */
class Box<T> {
	public var value:T = null;
	public var echo:T->T = function(value:T):T return value;
	public var exchange:T->T = {
		var previous:T = null;
		function(next:T):T {
			final before = previous;
			previous = next;
			return before;
		};
	};

	public function new() {}
}

/** A constructor-free child must initialize both its generic ancestor and its own field. */
class Leaf extends Box<String> {
	public var marker:Int = 3;
}

/** The independent native observer follows the generic field after forced collection. */
class Payload {
	public var number:Int;

	public function new(number:Int)
		this.number = number;
}
