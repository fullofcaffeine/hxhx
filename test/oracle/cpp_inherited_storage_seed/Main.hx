/** Constructor chaining and an upcast must keep one allocation and one inherited field. */
class Main {
	static function main():Void {
		final child = new Child(7);
		final base:Base = child;
		if (base.value != 7 || child.label != "child")
			throw "constructor chain lost its fields";
		base.value = 11;
		if (child.value != 11)
			throw "upcast copied inherited storage";
		child.value = 13;
		if (base.value != 13 || child.label != "child")
			throw "subclass storage does not share its base field";
	}
}

/** Base construction initializes the field later accessed through either receiver type. */
class Base {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** The additional field must not overwrite or replace inherited storage. */
class Child extends Base {
	public var label:String;

	public function new(value:Int) {
		super(value);
		label = "child";
	}
}
