/** Observe omission, explicit null, supplied effects, and parent construction through ordinary Haxe. */
class Main {
	static var effects:Int = 0;

	static function text():String {
		effects = effects * 10 + 1;
		return "set";
	}

	static function number():Int {
		effects = effects * 10 + 2;
		return 7;
	}

	static function main():Void {
		final absent = new Box();
		final explicit = new Box(null, null, null);
		final partial = new Box("part");
		final supplied = new Box(text(), number(), false);
		final child = new Child();
		if (absent.label != "absent" || absent.number != -1 || absent.flag != "absent")
			throw "omitted arguments changed";
		if (explicit.label != "absent" || explicit.number != -1 || explicit.flag != "absent")
			throw "explicit null changed";
		if (partial.label != "part" || partial.number != -1)
			throw "partial arguments changed";
		if (supplied.label != "set" || supplied.number != 7 || supplied.flag != "false")
			throw "supplied arguments changed";
		if (effects != 12)
			throw "arguments did not execute once in source order";
		if (child.label != "absent" || child.number != -1)
			throw "parent omissions changed";
	}
}

/** Parameter null checks must occur before optional scalars become ordinary field values. */
class Box {
	public var label:String;
	public var number:Int;
	public var flag:String;

	public function new(?label:String, ?number:Int, ?flag:Bool) {
		this.label = label == null ? "absent" : label;
		this.number = number == null ? -1 : number;
		this.flag = flag == null ? "absent" : flag ? "true" : "false";
	}
}

/** Parent construction initializes the existing child with omitted parameters. */
class Child extends Box {
	public function new() {
		super();
	}
}
