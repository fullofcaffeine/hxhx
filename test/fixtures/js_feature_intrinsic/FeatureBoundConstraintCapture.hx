/** Haxe 4.3.7 permits a stored generic callback to infer a type outside the original method constraint. */
class FeatureBoundConstraintCapture {
	static function main():Void {
		final receiver = new CaptureConstraintReceiver();
		final callback = receiver.echo;
		trace(callback(7));
	}
}

/** The capture keeps callable behavior while upstream permits a fresh unconstrained argument inference. */
class CaptureConstraintReceiver {
	public function new() {}

	public function echo<T:CaptureConstraintBase>(value:T):T {
		return value;
	}
}

/** The declaration constraint is deliberately unrelated to Int. */
class CaptureConstraintBase {
	public function new() {}
}
