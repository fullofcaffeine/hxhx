import FeatureBoundOptional.OptionalReceiver;

/** An optional trailing parameter must not make the required generic input optional. */
class FeatureBoundOptionalMissing {
	static function main():Void {
		final receiver = new OptionalReceiver();
		final echo = receiver.echo;
		final alias = echo;
		trace(alias());
	}
}
