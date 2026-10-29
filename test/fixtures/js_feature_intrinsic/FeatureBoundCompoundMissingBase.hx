import FeatureBoundCompound.CompoundNamed;
import FeatureBoundCompound.CompoundReceiver;

/** Satisfying the interface cannot conceal a missing class bound. */
class FeatureBoundCompoundMissingBase {
	static function main():Void {
		final receiver = new CompoundReceiver();
		receiver.echo(new NamedOnly());
	}
}

/** This argument supplies only the interface relationship. */
class NamedOnly implements CompoundNamed {
	public function new() {}

	public function name():String {
		return "incomplete";
	}
}
