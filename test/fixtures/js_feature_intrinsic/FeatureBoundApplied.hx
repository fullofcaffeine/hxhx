/** A method bound referring to its class parameter uses the receiver's exact application. */
class FeatureBoundApplied {
	static function main():Void {
		final receiver = new AppliedReceiver<AppliedBase>();
		trace(receiver.echo(new AppliedChild()).name());
		final inherited = new FixedAppliedReceiver();
		trace(inherited.echo(new AppliedChild()).name());
	}
}

/** U is a method binder whose bound is the independent class binder T. */
class AppliedReceiver<T> {
	public function new() {}

	public function echo<U:T>(value:U):U {
		return value;
	}
}

/** An inherited application must substitute the ancestor's arguments before checking U. */
class FixedAppliedReceiver extends AppliedReceiver<AppliedBase> {
	public function new() {
		super();
	}
}

/** This nominal base supplies the applied constraint. */
class AppliedBase {
	public function new() {}

	public function name():String {
		return "base";
	}
}

/** The constrained result preserves the actual child type and virtual behavior. */
class AppliedChild extends AppliedBase {
	public function new() {
		super();
	}

	override public function name():String {
		return "child";
	}
}
