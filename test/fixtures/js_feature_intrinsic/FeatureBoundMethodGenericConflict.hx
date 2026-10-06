import FeatureBoundMethodGeneric.MethodGenericReceiver;

/** One stored generic callback has one inferred type; later incompatible calls must fail. */
class FeatureBoundMethodGenericConflict {
	static function main():Void {
		final receiver = new MethodGenericReceiver();
		final callback = receiver.echo;
		trace(callback("text"));
		trace(callback(7));
	}
}
