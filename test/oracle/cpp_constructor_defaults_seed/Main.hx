/** Defaults initialize body values before capture, while supplied arguments retain source order. */
class Main {
	static var effects:Int = 0;

	static function text():String {
		effects = effects * 10 + 1;
		return "supplied";
	}

	static function number():Int {
		effects = effects * 10 + 2;
		return 9;
	}

	static function main():Void {
		final omitted = new Box();
		final absentNumber:Null<Int> = null;
		final absentFlag:Null<Bool> = null;
		final explicit = new Box(null, absentNumber, absentFlag);
		final supplied = new Box(text(), number(), false);
		final partial = new Box("partial");
		final zero = new Box("zero", 0, false);
		final child = new Child();
		if (omitted.label != "default" || omitted.number != 5 || !omitted.flag)
			throw "omitted defaults differ";
		if (explicit.label != "default" || explicit.number != 5 || !explicit.flag)
			throw "explicit null defaults differ";
		if (supplied.label != "supplied" || supplied.number != 9 || supplied.flag)
			throw "supplied values were replaced";
		if (partial.label != "partial" || partial.number != 5)
			throw "partial defaults differ";
		if (zero.number != 0 || zero.flag)
			throw "false or zero was mistaken for an absent argument";
		if (Defaults.LABEL != omitted.label || defaultNumber() != 6)
			throw "ordinary constant read or static default differs";
		if (defaultNumber(absentNumber) != 6 || questionNumber(null) != 6)
			throw "named call confused a nullable input with a literal scalar null";
		if (child.label != "default" || child.number != 5)
			throw "parent defaults differ";
		if (omitted.read() != "default" || explicit.read() != "default" || supplied.read() != "supplied")
			throw "captured parameter missed its default";
		if (effects != 12)
			throw "supplied arguments changed order or count";
	}

	static function defaultNumber(value:Int = 6):Int
		return value;

	static function questionNumber(?value:Int = 6):Int
		return value;
}

/** The default constant is owned by a declaration outside the constructor body. */
class Defaults {
	public static inline var WORD:String = "default";
	public static inline var LABEL:String = WORD;
}

/** Capture the initialized input so forced collection also checks its parameter cell. */
class Box {
	public var label:String;
	public var number:Int;
	public var flag:Bool;
	public var read:() -> String;

	public function new(label:String = Defaults.LABEL, number:Int = (2 + 3), flag:Bool = true) {
		this.label = label;
		this.number = number;
		this.flag = flag;
		read = () -> label;
	}
}

/** Parent entry applies defaults to the existing child receiver. */
class Child extends Box {
	public function new() {
		super();
	}
}
