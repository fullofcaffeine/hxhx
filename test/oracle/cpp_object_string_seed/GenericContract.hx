/** Generic applications retain their own method bodies while sharing Haxe class identity. */
class GenericContract {
	public static var calls:Int = 0;

	static function require(value:Bool, label:String):Void {
		if (!value)
			throw label;
	}

	static function printed(value:Printable):String
		return value.toString();

	static function main():Void {
		final first = new GenericBox<Int>(3);
		final second = new GenericBox<String>("text");
		final repeated = new GenericBox<Int>(4);
		require(Std.string(first) == "[3]", "Int string application");
		require(Std.string(second) == "[text]", "String string application");
		require(Std.string(repeated) == "[4]", "repeated application");
		require(printed(first) == "[3]" && printed(second) == "[text]", "interface applications");
		final intChild:GenericBox<Int> = new GenericChild<Int>(5);
		final stringChild:GenericBox<String> = new GenericChild<String>("child");
		require(Std.string(intChild) == "child:[5]", "inherited Int application");
		require(Std.string(stringChild) == "child:[child]", "inherited String application");
		require(printed(intChild) == "child:[5]" && printed(stringChild) == "child:[child]", "interface overrides");
		require(first.read() == 3 && second.read() == "text", "typed field reads");
		require(Std.isOfType(first, GenericBox) && Std.isOfType(second, GenericBox), "generic class membership");
		require(Std.isOfType(intChild, GenericBox) && Std.isOfType(stringChild, GenericChild), "generic inherited membership");
		final intClass:Class<GenericBox<Int>> = GenericBox;
		final stringClass:Class<GenericBox<String>> = GenericBox;
		final left:Dynamic = intClass;
		final right:Dynamic = stringClass;
		require(left == right, "public generic class identity");
		require(calls == 9, "conversion evaluation count");
	}
}

/** An erased interface call must still select the receiver's exact compiled application. */
interface Printable {
	public function toString():String;
}

/** The declared field remains generic even when an instance has a concrete argument. */
class GenericBox<T> implements Printable {
	final value:T;

	public function new(value:T)
		this.value = value;

	public function read():T
		return value;

	public function toString():String {
		GenericContract.calls++;
		return "[" + Std.string(value) + "]";
	}
}

/** Explicit super dispatch must preserve the actual allocation's application identity. */
class GenericChild<T> extends GenericBox<T> {
	public function new(value:T)
		super(value);

	override public function toString():String
		return "child:" + super.toString();
}
