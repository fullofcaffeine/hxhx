/** Constructor operands must infer owner arguments and keep their runtime evaluation order. */
class ConstructorCases {
	static function argument():String {
		Sys.println("argument");
		return "text";
	}

	static function marker():Int {
		Sys.println("marker");
		return 0;
	}

	static function main():Void {
		final text = new Box(argument(), marker());
		final number = new Box(7);
		final explicit = new Box<String>("written");
		final widened = new Box<Float>(1);
		final nested = new Box(new Box("inner"));
		Sys.println(text.get());
		Sys.println(number.get());
		Sys.println(explicit.get());
		Sys.println(widened.get() + 0.5);
		Sys.println(nested.get().get());
	}
}

/** Each allocation's T comes from its own value operand, including another Box. */
class Box<T> {
	var value:T;

	public function new(value:T, marker:Int = 0) {
		this.value = value;
	}

	public function get():T {
		return value;
	}
}
