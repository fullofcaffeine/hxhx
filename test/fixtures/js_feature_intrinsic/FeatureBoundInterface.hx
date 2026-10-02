/** Interface constraints preserve the concrete result through inherited implementations. */
class FeatureBoundInterface {
	static function main():Void {
		final receiver = new InterfaceReceiver();
		trace(receiver.echo(new InterfaceChild()).value());
	}
}

/** The argument must implement this exact interface with the required type argument. */
interface BoundValue<T> {
	public function value():T;
}

/** A nominal interface bound must not erase the inferred method result. */
class InterfaceReceiver {
	public function new() {}

	public function echo<T:BoundValue<String>>(value:T):T {
		return value;
	}
}

/** The child receives its interface application through this superclass. */
class InterfaceBase implements BoundValue<String> {
	public function new() {}

	public function value():String {
		return "interface";
	}
}

/** This concrete type must remain the direct call result. */
class InterfaceChild extends InterfaceBase {
	public function new() {
		super();
	}
}
