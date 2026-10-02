import FeatureBoundInterface.InterfaceReceiver;

/** Matching method shapes do not establish a nominal interface relationship. */
class FeatureBoundInterfaceUndeclared {
	static function main():Void {
		final receiver = new InterfaceReceiver();
		receiver.echo(new UndeclaredValue());
	}
}

/** This class deliberately does not declare the required interface. */
class UndeclaredValue {
	public function new() {}

	public function value():String {
		return "undeclared";
	}
}
