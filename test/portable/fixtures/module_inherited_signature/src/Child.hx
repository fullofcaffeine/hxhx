/** Overrides behavior while retaining the inherited object's state. */
class Child extends Base {
	public function new(count:Int) {
		super(count);
	}

	override public function describe():String {
		return First.label("child", count);
	}
}
