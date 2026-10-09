/** Passing this into a constructor must retain the enclosing class's generic binder. */
class SelfCases {
	static function main():Void {
		final box = new Box("self");
		Sys.println(box.wrap().get());
	}
}

/** The receiver's T must remain identical in Box<T> and Holder<T>. */
class Box<T> {
	public var value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function wrap():Holder<T> {
		return new Holder(this);
	}
}

/** A constructor consumes the generic receiver as an ordinary nominal argument. */
class Holder<T> {
	var box:Box<T>;

	public function new(box:Box<T>) {
		this.box = box;
	}

	public function get():T {
		return box.value;
	}
}
