import FeatureBoundInterface.BoundValue;
import FeatureBoundInterface.InterfaceReceiver;

/** Implementing the interface with Int cannot satisfy its String application. */
class FeatureBoundInterfaceConflict {
	static function main():Void {
		final receiver = new InterfaceReceiver();
		receiver.echo(new IntegerValue());
	}
}

/** This is a valid interface implementation with the wrong argument for the call. */
class IntegerValue implements BoundValue<Int> {
	public function new() {}

	public function value():Int {
		return 7;
	}
}
