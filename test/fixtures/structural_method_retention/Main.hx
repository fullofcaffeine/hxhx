/** A named structural contract keeps method syntax resolved independently of inline hints. */
typedef Reader = {
	function value():Int;
	function exposed():Int;
}

typedef GenericReader<T> = {function read():T;}

/** Calls through a record signature must retain the concrete class implementation. */
class Main {
	static function provide():Reader {
		return new Answer();
	}

	static function main():Void {
		new Unrelated();
		if (provide().value() != 7)
			throw "structural method result";
		var stored:Reader = new Answer();
		if (stored.value() != 7 || take(new Answer()) != 7)
			throw "structural local or argument";
		if (generic().read() != 19)
			throw "inherited generic structural method";
		// Feature intrinsics are upstream's untyped compiler API. Only these
		// booleans cross that boundary; ordinary fixture values stay typed.
		if (untyped __feature__("retention.exposed", false, true))
			throw "unused exposed method must contribute its feature";
		if (untyped __feature__("retention.unrelated", true, false))
			throw "unrelated same-name method must stay unreachable";
	}

	static function take(value:Reader):Int
		return value.value();

	static function generic():GenericReader<Int>
		return new Child();
}

/** The caller sees only the structural return type of Main.provide. */
class Answer {
	public function new() {}

	public function value():Int {
		return 7;
	}

	public function exposed():Int {
		untyped __define_feature__("retention.exposed", true);
		return 9;
	}
}

/** Construction alone must not retain similarly named instance methods. */
class Unrelated {
	public function new() {}

	public function value():Int {
		untyped __define_feature__("retention.unrelated", true);
		return 11;
	}

	public function exposed():Int
		return 13;
}

/** The structural return keeps the inherited implementation and its concrete type. */
class Base<T> {
	final item:T;

	public function new(item:T) {
		this.item = item;
	}

	public function read():T
		return item;
}

class Child extends Base<Int> {
	public function new() {
		super(19);
	}
}
