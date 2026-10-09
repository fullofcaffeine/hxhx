/** Empty object constraints retain the concrete object and its original identity. */
class FeatureBoundEmptyObject {
	static function main():Void {
		final receiver = new EmptyObjectReceiver();
		final original = new EmptyObjectValue();
		final selected = receiver.echo(original);
		trace(selected == original);
		trace(selected.name());
		trace(receiver.echo("text"));
	}
}

/** The bound permits object-compatible values while inference preserves each exact result type. */
class EmptyObjectReceiver {
	public function new() {}

	public function echo<T:{}>(value:T):T {
		return value;
	}
}

/** A returned method call requires the inferred concrete class, not an erased empty record. */
class EmptyObjectValue {
	public function new() {}

	public function name():String {
		return "object";
	}
}
