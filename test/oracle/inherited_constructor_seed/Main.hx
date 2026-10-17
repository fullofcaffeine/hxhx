/** Observe inherited constructor arguments, defaults, and each class's initializer order. */
class Main {
	static var events:Int = 0;

	public static function mark(value:Int):Int {
		events = events * 10 + value;
		return value;
	}

	static function main():Void {
		final explicit = new Child(mark(7));
		if (events != 743172 || explicit.child != 4 || explicit.middle != 3 || explicit.base != 1)
			throw "inherited constructor order differs";
		events = 0;
		final defaults = new Child();
		if (events != 43182 || defaults.base != 1)
			throw "inherited constructor default differs";
		final generic = new GenericLeaf(new Box<Int>());
	}
}

/** The inherited body retains its own declaration and field initializer. */
class Base {
	public var base:Int = Main.mark(1);

	public function new(value:Int = 8) {
		Main.mark(value);
		Main.mark(2);
	}
}

/** Omission forwards parameters while retaining this class's initialization obligation. */
class Middle extends Base {
	public var middle:Int = Main.mark(3);
}

/** Allocation retains this type even though Base owns the executed constructor. */
class Child extends Middle {
	public var child:Int = Main.mark(4);
}

/** A nested argument distinguishes real substitution from copying a parameter name. */
class Box<T> {
	public function new() {}
}

/** The selected argument binder belongs here, after substitution through both child edges. */
class GenericBase<A> {
	public function new(value:A) {}
}

/** The superclass embeds this class's binder inside another nominal argument. */
class GenericMiddle<B> extends GenericBase<Box<B>> {}

/** This concrete edge supplies Int to both ancestor substitutions. */
class GenericLeaf extends GenericMiddle<Int> {}
