/** Exercise applied generic fields through ordinary assignments, aliases, and inherited receivers. */
class Main {
	public static var held:Box<Payload>;

	static function main():Void {
		final ints = new Box<Int>();
		final strings = new Box<String>();
		final leaf = new Leaf();
		final initial:Int = ints.value;
		final nullable:Null<Int> = ints.value;
		if (initial != 0 || ints.value == 0 || nullable != null)
			throw "generic null did not convert at the concrete Int destination";
		final read:Void->Int = function():Int return ints.value;
		final write:Int->Void = function(value:Int):Void {
			ints.value = value;
		};
		if (read() != 0)
			throw "captured generic read missed its concrete result conversion";
		final copied = new Box<Int>();
		copied.value = ints.value;
		final copiedNull:Null<Int> = copied.value;
		if (copiedNull != null)
			throw "generic field copy coerced its null storage";
		copied.value += 2;
		if (copied.value != 2)
			throw "generic compound update did not convert at its numeric operation";
		final flags = new Box<Bool>();
		final initialFlag:Bool = flags.value;
		final nullableFlag:Null<Bool> = flags.value;
		if (initialFlag || flags.value == false || nullableFlag != null)
			throw "generic Boolean null lost its storage or conversion boundary";
		flags.value = true;
		if (flags.value != true || !flags.value)
			throw "generic Boolean write or comparison failed";
		write(7);
		strings.value = "word";
		leaf.value = "leaf";
		if (ints.value != 7 || read() != 7 || strings.value != "word" || leaf.value != "leaf")
			throw "generic applications selected the wrong field";
		final alias = strings;
		alias.value = "changed";
		if (strings.value != "changed" || ints.value != 7)
			throw "generic field writes lost alias identity or changed another instance";
		final nullableBox:Null<Box<Int>> = ints;
		if (nullableBox.value != 7)
			throw "nullable receiver changed its applied field";
		held = new Box<Payload>();
		held.value = new Payload(9);
		final temporary = new Payload(2);
		if (held.value.number != 9 || temporary.number != 2)
			throw "generic reference field lost its managed payload";
	}
}

/** The field's declaration remains T even when a caller knows its concrete application. */
class Box<T> {
	public var value:T;

	public function new() {}
}

/** Resolve the field through both generic ancestor edges. */
class Middle<T> extends Box<T> {}

/** The concrete child exercises inherited field selection without declaring a constructor. */
class Leaf extends Middle<String> {}

/** A separately allocated payload makes generic field tracing observable under forced collection. */
class Payload {
	public var number:Int;

	public function new(number:Int) {
		this.number = number;
	}
}
