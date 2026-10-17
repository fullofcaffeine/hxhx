/** Compare implicit forwarding, explicit super calls, and captured initializer values at runtime. */
class Main {
	static var events:Int = 0;

	public static function mark(value:Int):Int {
		events = events * 10 + value;
		return value;
	}

	static function main():Void {
		final child = new Child(mark(7));
		if (events != 743172 || child.child != 4 || child.middle != 3 || child.base != 1)
			throw "inherited initializer order differs";
		events = 0;
		final defaults = new Child();
		if (events != 43182 || defaults.base != 1)
			throw "inherited default differs";
		events = 0;
		final explicit = new Explicit();
		if (events != 965431520 || explicit.own != 9 || explicit.child != 4)
			throw "explicit super through omitted constructors differs";
		final first = new CallbackChild();
		final second = new CallbackChild();
		if (first.callback() != 22 || first.callback() != 23 || second.callback() != 22)
			throw "forwarded initializer capture differs";
		events = 0;
		final direct = new Base(6);
		if (events != 162 || direct.base != 1)
			throw "direct ancestor construction borrowed child initializers";
		events = 0;
		final sibling = new Sibling(4);
		if (events != 5142 || sibling.sibling != 5)
			throw "sibling construction reused another forwarding path";
	}
}

/** The real constructor body must run after each constructor-free child's fields. */
class Base {
	public var base:Int = Main.mark(1);

	public function new(value:Int = 8) {
		Main.mark(value);
		Main.mark(2);
	}
}

/** This class contributes a field, but no callable body. */
class Middle extends Base {
	public var middle:Int = Main.mark(3);
}

/** This allocated child retains its own storage and forwards the ancestor's parameters. */
class Child extends Middle {
	public var child:Int = Main.mark(4);
}

/** This class selects the same Base body through a different initializer path. */
class Sibling extends Base {
	public var sibling:Int = Main.mark(5);
}

/** A written super call must execute the same implicit chain on the existing receiver. */
class Explicit extends Child {
	public var own:Int = Main.mark(9);

	public function new() {
		Main.mark(6);
		super(Main.mark(5));
		Main.mark(0);
	}
}

/** Allocation inside a callback can collect while its captured payload remains live. */
class Payload {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** A concrete authored body supplies the implicit child's constructor. */
class CallbackBase {
	public function new() {}
}

/** Each child invocation owns a fresh captured payload and a field-owned closure. */
class CallbackChild extends CallbackBase {
	public var callback:Void->Int = {
		var held = new Payload(21);
		function() {
			var discarded = new Payload(99);
			held.value += 1;
			return held.value;
		};
	};
}
