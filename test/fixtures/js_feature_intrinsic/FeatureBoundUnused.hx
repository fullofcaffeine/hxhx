/** Unused generic values are legal even when no caller supplies a concrete method type. */
class FeatureBoundUnused {
	static function main():Void {
		final receiver = new UnusedReceiver();
		receiver.echo(null);
		final unused = receiver.echo(null);
		final callback = receiver.echo;
		trace("done");
	}
}

/** The observable call effect must survive even when the generic result is unused. */
class UnusedReceiver {
	public function new() {}

	public function echo<T>(value:T):T {
		trace("called");
		return value;
	}
}
