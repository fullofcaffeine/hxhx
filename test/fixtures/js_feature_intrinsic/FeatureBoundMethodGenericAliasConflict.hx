import FeatureBoundMethodGeneric.MethodGenericReceiver;

/** Copying a callback does not allocate another set of method inference variables. */
class FeatureBoundMethodGenericAliasConflict {
	static function main():Void {
		final receiver = new MethodGenericReceiver();
		final callback = receiver.echo;
		final alias = callback;
		trace(callback("text"));
		trace(alias(7));
	}
}
