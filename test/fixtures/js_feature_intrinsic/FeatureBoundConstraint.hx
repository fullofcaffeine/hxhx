/** A captured method may infer a subtype that satisfies its declared generic constraint. */
class FeatureBoundConstraint {
	static function main():Void {
		final receiver = new ConstraintReceiver();
		final callback = receiver.echo;
		final result = callback(new ConstraintChild());
		trace(result.name());
		trace(receiver.echo(new ConstraintChild()).name());
	}
}

/** The method parameter is restricted to the declared base class. */
class ConstraintReceiver {
	public function new() {}

	public function echo<T:ConstraintBase>(value:T):T {
		return value;
	}
}

/** A nominal constraint is a semantic owner, not just a matching method shape. */
class ConstraintBase {
	public function new() {}

	public function name():String {
		return "base";
	}
}

/** This subclass is a valid argument for the constrained capture. */
class ConstraintChild extends ConstraintBase {
	public function new() {
		super();
	}

	override public function name():String {
		return "child";
	}
}
