/** Base construction must use this same object and its overridden method. */
class Derived extends Base {
	public var derivedValue:Int = Base.mark("derived-field", 5);

	public function new() {
		Sys.println("derived-before");
		super(Base.mark("super-argument", 7));
		Sys.println("derived-after");
	}

	override public function describe():String {
		return "derived";
	}

	public function adjust():Void {
		setBase(baseValue + 1);
	}
}
