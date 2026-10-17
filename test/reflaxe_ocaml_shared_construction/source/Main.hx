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

/** Three names distinguish Haxe's initializer order from both declaration and alphabetical order. */
class OrderedFields {
	public var zeta:Int = Main.record("ordered-zeta", 1);
	public var alpha:Int = Main.record("ordered-alpha", 2);
	public var middle:Int = Main.record("ordered-middle", 3);

	public function new() {
		Main.events.push("ordered-body");
	}
}

/** An inherited constructor must forward its argument to the original receiver. */
class ParameterParent {
	public var seed:Int;

	public function new(seed:Int) {
		this.seed = seed;
		Main.events.push("parameter-parent-body");
	}
}

/** Haxe supplies the omitted constructor, including local initialization before super. */
class ImplicitChild extends ParameterParent {
	public var zeta:Int = Main.record("implicit-zeta", 4);
	public var alpha:Int = Main.record("implicit-alpha", 5);
	public var middle:Int = Main.record("implicit-middle", 6);
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
		if (Type.getClass(first) != Item)
			throw "ordinary allocation lost its runtime class";
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
		final emptyItem = Type.createEmptyInstance(Item);
		if (Type.getClass(emptyItem) != Item)
			throw "empty allocation lost its runtime class";
		if (events.length != 0 || Item.last != retained)
			throw "empty allocation ran field initializers or the constructor";
		final child = new Child();
		if (events.join(",") != "child-field,base-field,base-body,child-body")
			throw "inherited initialization order: " + events.join(",");
		final parent:Parent = child;
		if (Type.getClass(child) != Child || Type.getClass(parent) != Child)
			throw "inherited allocation or upcast lost its most-derived runtime class";
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
		final emptyChild = Type.createEmptyInstance(Child);
		if (Type.getClass(emptyChild) != Child)
			throw "empty inherited allocation lost its runtime class";
		if (events.length != 0)
			throw "empty inherited allocation ran initializers or constructors";
		final ordered = new OrderedFields();
		if (events.join(",") != "ordered-middle,ordered-alpha,ordered-zeta,ordered-body"
			|| ordered.zeta != 1
			|| ordered.alpha != 2
			|| ordered.middle != 3)
			throw "multiple field initializer order: " + events.join(",");
		events = [];
		final implicit = new ImplicitChild(7);
		if (events.join(",") != "implicit-middle,implicit-alpha,implicit-zeta,parameter-parent-body"
			|| implicit.zeta != 4
			|| implicit.alpha != 5
			|| implicit.middle != 6
			|| implicit.seed != 7)
			throw "omitted constructor initialization or arguments: " + events.join(",");
		events = [];
		final emptyOrdered = Type.createEmptyInstance(OrderedFields);
		final emptyImplicit = Type.createEmptyInstance(ImplicitChild);
		if (Type.getClass(ordered) != OrderedFields
			|| Type.getClass(implicit) != ImplicitChild
			|| Type.getClass(emptyOrdered) != OrderedFields
			|| Type.getClass(emptyImplicit) != ImplicitChild)
			throw "explicit or omitted constructor lost its runtime class";
		if (events.length != 0)
			throw "empty allocation ran ordered or omitted constructor effects";
		Sys.println("construction:ok");
	}
}
