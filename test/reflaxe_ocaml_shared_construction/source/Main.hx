/** Constructor effects must retain their order, receiver and partially initialized state. */
class Item {
	public static var last:Null<Item>;

	public var value:Int = initialize();

	static function initialize():Int {
		Main.events.push("field");
		return 1;
	}

	public function new(seed:Int, fail:Bool) {
		Main.events.push("body");
		if (value != 1)
			throw "field initializer did not run before the constructor";
		last = this;
		value = seed;
		if (fail)
			throw "stop";
	}
}

/** Inherited storage and virtual calls must use the same initialized receiver. */
class Parent {
	public var base:Int = Main.record("base-field", 2);

	public function new() {
		Main.events.push("base-body");
	}

	public function read():Int {
		return base;
	}
}

/** Zero-argument construction also initializes distinct mutable array fields. */
class Child extends Parent {
	public var values:Array<Int> = [Main.record("child-field", 3)];

	public function new() {
		super();
		Main.events.push("child-body");
	}

	override public function read():Int {
		return base + values[0];
	}
}

/** Exercise allocation through ordinary Haxe, without generated-source repairs. */
class Main {
	public static var events:Array<String> = [];

	public static function record(label:String, value:Int):Int {
		events.push(label);
		return value;
	}

	static function main():Void {
		final first = new Item(7, false);
		if (first.value != 7 || events.join(",") != "field,body" || Item.last != first)
			throw "first constructor order or receiver: value="
				+ first.value
				+ " events="
				+ events.join(",")
				+ " retained="
				+ (Item.last == first);
		events = [];
		final second = new Item(11, false);
		if (first == second || first.value != 7 || second.value != 11 || events.join(",") != "field,body")
			throw "constructor instances share state";
		events = [];
		var failed = false;
		try {
			new Item(19, true);
		} catch (error:String) {
			if (error != "stop")
				throw error;
			failed = true;
		}
		final retained = Item.last;
		if (!failed || events.join(",") != "field,body" || retained == null || retained.value != 19)
			throw "throwing constructor lost its effects";
		events = [];
		Type.createEmptyInstance(Item);
		if (events.length != 0 || Item.last != retained)
			throw "empty allocation ran field initializers or the constructor";
		final child = new Child();
		if (events.join(",") != "child-field,base-field,base-body,child-body")
			throw "inherited initialization order: " + events.join(",");
		final parent:Parent = child;
		if (parent.read() != 5)
			throw "inherited constructor storage or dispatch differs";
		events = [];
		final other = new Child();
		if (events.join(",") != "child-field,base-field,base-body,child-body")
			throw "repeated inherited initialization order: " + events.join(",");
		child.values.push(8);
		if (other.values.length != 1 || child.values.length != 2)
			throw "inherited instances share array storage";
		events = [];
		Type.createEmptyInstance(Child);
		if (events.length != 0)
			throw "empty inherited allocation ran initializers or constructors";
		Sys.println("construction:ok");
	}
}
