/** Bound callbacks keep the receiver's concrete class parameters, including inherited specializations. */
class FeatureBoundGeneric {
	static function main():Void {
		final strings = new GenericReceiver<String>();
		final numbers = new GenericReceiver<Int>();
		final child = new StringReceiver();
		final text = strings.echo;
		final number = numbers.echo;
		final inherited = child.echo;
		trace(text("text"));
		trace(number(7));
		trace(inherited("inherited"));
		trace(strings.capture()("implicit"));
	}
}

/** Class parameters remain declaration binders until a concrete receiver selects this method. */
class GenericReceiver<T> {
	public function new() {}

	public function echo(value:T):T {
		return value;
	}

	public function capture():T->T {
		return echo;
	}
}

/** The ancestor application supplies String without adding an overriding declaration. */
class StringReceiver extends GenericReceiver<String> {
	public function new() {
		super();
	}
}
