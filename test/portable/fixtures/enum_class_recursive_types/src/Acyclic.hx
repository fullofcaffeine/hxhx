enum Box {
	Payload(value:Value);
}

/** A payload can depend on a class without forming a recursive component. */
class Value {
	public final amount:Int;

	public function new(amount:Int) {
		this.amount = amount;
	}
}

/** Read an acyclic enum payload after native type checking. */
class Acyclic {
	public static function value():Int {
		return switch (Box.Payload(new Value(7))) {
			case Payload(value): value.amount;
		};
	}
}
