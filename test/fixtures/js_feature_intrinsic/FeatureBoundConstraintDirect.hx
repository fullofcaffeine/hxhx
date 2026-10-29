import FeatureBoundConstraint.ConstraintReceiver;

/** A direct call retains the method declaration's constraint in upstream Haxe. */
class FeatureBoundConstraintDirect {
	static function main():Void {
		final receiver = new ConstraintReceiver();
		trace(receiver.echo(7));
	}
}
