import FeatureBoundCompound.CompoundBase;
import FeatureBoundCompound.CompoundReceiver;

/** Satisfying the first bound cannot conceal a missing second bound. */
class FeatureBoundCompoundMissingInterface {
	static function main():Void {
		final receiver = new CompoundReceiver();
		receiver.echo(new CompoundBase());
	}
}
