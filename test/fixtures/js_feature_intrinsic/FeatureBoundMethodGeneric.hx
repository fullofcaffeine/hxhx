/** Separate reads of a generic method can select independent callback types. */
class FeatureBoundMethodGeneric {
	static function main():Void {
		final receiver = new MethodGenericReceiver();
		final text = receiver.echo;
		final number = receiver.echo;
		trace(text("text"));
		trace(number(7));
		trace(receiver.echo("direct"));
		trace((receiver.echo)("wrapped"));
	}
}

/** This parameter belongs to the method, rather than to its receiver class. */
class MethodGenericReceiver {
	public function new() {}

	public function echo<T>(value:T):T {
		return value;
	}
}
