package foreign;

import FeatureBoundConstraint.ConstraintReceiver;

/** A caller's same-named type cannot satisfy a bound owned by another module. */
class FeatureBoundConstraintForeign {
	static function main():Void {
		final receiver = new ConstraintReceiver();
		receiver.echo(new ConstraintBase());
	}
}

/** This unrelated declaration deliberately shares the constraint's short name. */
class ConstraintBase {
	public function new() {}
}
