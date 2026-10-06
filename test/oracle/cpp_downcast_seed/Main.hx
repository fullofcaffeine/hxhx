/** Downcasts select a class view without allocating a replacement object. */
class Main {
	static var effects:Int = 0;

	/** The native observer supplies collecting or throwing operands to this exact authored call. */
	public static function boundary(value:Void->Base, target:Void->Class<Child>):Child {
		return Std.downcast(value(), target());
	}

	static function value():Base {
		effects = effects * 10 + 1;
		return new Child(7);
	}

	static function target():Class<Child> {
		effects = effects * 10 + 2;
		final temporary = [1, 2];
		if (temporary.length != 2)
			throw "target allocation";
		return Child;
	}

	static function main():Void {
		final child = new Child(3);
		final base:Base = child;
		final narrowed = Std.downcast(base, Child);
		if (narrowed == null || narrowed != child)
			throw "downcast identity";
		if (Std.downcast(Std.downcast(base, Child), Child) != child)
			throw "nested downcast identity";
		final descendant:Base = new Grandchild(5);
		final inherited = Std.downcast(descendant, Child);
		if (inherited == null || inherited.value != 5 || Std.downcast(descendant, Base) != descendant)
			throw "inherited downcast identity";
		narrowed.value = 9;
		if (base.value != 9)
			throw "downcast shared mutation";
		if (Std.downcast(new Base(1), Child) != null)
			throw "base mismatch";
		final sibling:Base = new Other(1);
		if (Std.downcast(sibling, Child) != null)
			throw "sibling mismatch";
		final absent:Base = null;
		if (Std.downcast(absent, Child) != null)
			throw "null value";
		final selected:Class<Child> = Child;
		if (Std.downcast(base, selected) != child)
			throw "stored class";
		final ordered = Std.downcast(value(), target());
		if (ordered == null || ordered.value != 7 || effects != 12)
			throw "ordered operands";
	}
}

/** Mutable state makes the original allocation observable after narrowing. */
class Base {
	public var value:Int;

	public function new(value:Int)
		this.value = value;
}

class Child extends Base {
	public function new(value:Int)
		super(value);
}

class Other extends Base {
	public function new(value:Int)
		super(value);
}

/** A deeper subtype must match an ancestor class descriptor. */
class Grandchild extends Child {
	public function new(value:Int)
		super(value);
}
