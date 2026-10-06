import FeatureBoundOptional.OptionalReceiver;

/** Preserving optional parameters must not permit arguments beyond the declared signature. */
class FeatureBoundOptionalExtra {
	static function main():Void {
		final receiver = new OptionalReceiver();
		final echo = receiver.echo;
		trace(echo("text", 1, 2));
	}
}
