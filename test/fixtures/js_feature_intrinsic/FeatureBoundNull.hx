/** Null supplies no concrete generic argument; contexts and later uses can determine the result. */
class FeatureBoundNull {
	static function main():Void {
		final receiver = new NullBoundReceiver();
		var base:NullBoundBase = receiver.echo(null);
		trace(base == null);
		final child:NullBoundChild = (receiver.echo)(null);
		trace(child == null);
		final number:Int = receiver.echo(null);
		trace(number == null);
		var later = receiver.echo(null);
		var alias = later;
		alias = new NullBoundChild();
		trace(alias.name());
		trace(take(receiver.echo(null)));
		trace(make() == null);
		base = new NullBoundChild();
		trace(base.name());
	}

	static function take(value:NullBoundBase):Bool {
		return value == null;
	}

	static function make():NullBoundChild {
		final receiver = new NullBoundReceiver();
		return receiver.echo(null);
	}
}

/** The constraint applies to concrete argument evidence; null-only calls remain inferable upstream. */
class NullBoundReceiver {
	public function new() {}

	public function echo<T:NullBoundBase>(value:T):T {
		return value;
	}
}

/** A valid nominal context for the result. */
class NullBoundBase {
	public function new() {}

	public function name():String {
		return "base";
	}
}

/** A more precise context and a later assignment must preserve this type. */
class NullBoundChild extends NullBoundBase {
	public function new() {
		super();
	}

	override public function name():String {
		return "child";
	}
}
