/** Independent observations for generic layout and runtime identity decisions. */
class Main {
	static function main():Void {
		final ints = new Box<Int>();
		final strings = new Box<String>();
		Sys.println("same-class=" + (Type.getClass(ints) == Box && Type.getClass(strings) == Box));
		Sys.println("class-value=" + (Type.getClass(ints) == Box));
		Sys.println("int-unset=" + ints.isUnset());
		Sys.println("string-unset=" + (strings.value == null));
		Sys.println("plain-int=" + ints.plain);
		final stored:Int = ints.value;
		final returned:Int = ints.get();
		Sys.println("stored-unset-int=" + stored);
		Sys.println("returned-unset-int=" + returned);
		ints.value = 7;
		strings.value = "word";
		Sys.println("int-set=" + ints.get());
		Sys.println("string-set=" + strings.get());
		final leaf = new Leaf();
		Sys.println("leaf-box=" + Std.isOfType(leaf, Box));
		Sys.println("leaf-class=" + (Type.getClass(leaf) == Leaf));
		Sys.println("leaf-unset=" + leaf.isUnset());
		Sys.println("middle-super=" + (Type.getSuperClass(Middle) == Box));
	}
}

/** A declared T field preserves null even when a caller applies Int. */
class Box<T> {
	public var value:T;
	public var plain:Int;

	public function new() {}

	public function get():T
		return value;

	/** Test inside the generic body; static C++ rejects a caller's direct Int/null comparison. */
	public function isUnset():Bool
		return value == null;
}

/** Each superclass edge must retain the argument bound to its own T declaration. */
class Middle<T> extends Box<T> {}

/** A concrete leaf keeps its own class identity and its generic ancestor's field behavior. */
class Leaf extends Middle<Int> {}
