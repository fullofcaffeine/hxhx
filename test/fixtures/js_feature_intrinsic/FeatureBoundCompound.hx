/** Every member of a compound method bound must hold for the inferred argument. */
class FeatureBoundCompound {
	static function main():Void {
		final receiver = new CompoundReceiver();
		trace(receiver.echo(new CompoundChild()).name());
	}
}

/** The method requires both nominal relationships, while returning the concrete argument type. */
class CompoundReceiver {
	public function new() {}

	public function echo<T:CompoundBase & CompoundNamed>(value:T):T {
		return value;
	}
}

/** The class half of the compound bound. */
class CompoundBase {
	public function new() {}
}

/** The interface half of the compound bound. */
interface CompoundNamed {
	public function name():String;
}

/** This argument satisfies both constraints. */
class CompoundChild extends CompoundBase implements CompoundNamed {
	public function new() {
		super();
	}

	public function name():String {
		return "compound";
	}
}
