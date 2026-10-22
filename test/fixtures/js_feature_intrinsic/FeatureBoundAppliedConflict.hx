import FeatureBoundApplied.AppliedReceiver;
import FeatureBoundApplied.AppliedBase;

/** Int does not satisfy the Base bound supplied by this receiver application. */
class FeatureBoundAppliedConflict {
	static function main():Void {
		final receiver = new AppliedReceiver<AppliedBase>();
		receiver.echo(7);
	}
}
