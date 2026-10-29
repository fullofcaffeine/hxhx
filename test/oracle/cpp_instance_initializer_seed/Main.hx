/** Construction effects distinguish source field order from physical layout order. */
class Main {
	public static var events:Int = 0;

	public static function mark(value:Int):Int {
		events = events * 10 + value;
		return value;
	}

	static function main():Void {
		final value = new Child(mark(7));
		if (events != 786934125 || value.first != 1 || value.z != 3 || value.a != 6 || value.payload.value != 8)
			throw "instance initializer order or stored value differs";
	}
}

/** Parent fields initialize at the explicit super call, before the parent body. */
class Parent {
	public var first:Int = Main.mark(1);

	public function new() {
		Main.mark(2);
	}
}

/** Haxe 4.3.7 runs initialized fields in reverse declaration order, independently of layout. */
class Child extends Parent {
	public var z:Int = {
		var digit = Main.mark(9);
		digit -= 6;
		Main.mark(digit);
	};
	public final a:Int = Main.mark(6);
	public var payload:Payload = {
		var held = new Payload(8);
		new CollectionTrigger();
		held;
	};

	public function new(argument:Int) {
		if (argument != 7)
			throw "constructor argument changed";
		Main.mark(4);
		super();
		Main.mark(5);
	}
}

/** Allocation inside a field initializer must preserve the outer receiver's root. */
class Payload {
	public var value:Int;

	public function new(value:Int) {
		this.value = Main.mark(value);
	}
}

/** A second allocation forces collection while the initializer still owns its local payload. */
class CollectionTrigger {
	public function new() {}
}
