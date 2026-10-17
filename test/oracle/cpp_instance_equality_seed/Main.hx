/** Allocation identity must survive aliases, upcasts, nulls, and allocating comparison operands. */
class Main {
	static var events:Int = 0;

	static function left():Base {
		events = events * 10 + 1;
		return new Base(7);
	}

	static function right():Base {
		events = events * 10 + 2;
		return new Base(7);
	}

	static function main():Void {
		final first = new Base(7);
		final alias = first;
		final second = new Base(7);
		if (first != alias || first == second || first.value != second.value)
			throw "instance identity became field equality";
		final child = new Child();
		final parent:Base = child;
		if (child != parent || parent != child || parent == first)
			throw "upcast changed instance identity";
		final absent:Base = null;
		final alsoAbsent:Base = null;
		if (absent != alsoAbsent || absent == first || first == absent)
			throw "reference comparison lost null identity";
		if (left() == right() || events != 12)
			throw "comparison repeated or reordered allocating operands";
	}
}

/** Equal field values deliberately do not imply equal object identity. */
class Base {
	public var value:Int;

	public function new(value:Int)
		this.value = value;
}

/** A base reference and derived reference identify the same allocation. */
class Child extends Base {
	public function new()
		super(7);
}
