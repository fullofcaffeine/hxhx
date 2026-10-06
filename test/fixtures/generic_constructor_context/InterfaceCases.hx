/** Constructor inference follows the receiver's declared generic interface. */
class InterfaceCases {
	static function main():Void {
		final box = new Box("interface");
		Sys.println(box.wrap().get());
	}
}

/** Consumers can obtain a value without depending on its concrete storage class. */
interface View<T> {
	function get():T;
}

/** The interface's argument must retain the enclosing class binder. */
class Box<T> implements View<T> {
	var value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function get():T {
		return value;
	}

	public function wrap():Holder<T> {
		return new Holder(this);
	}
}

/** This constructor accepts the interface rather than the concrete Box. */
class Holder<T> {
	var view:View<T>;

	public function new(view:View<T>) {
		this.view = view;
	}

	public function get():T {
		return view.get();
	}
}
