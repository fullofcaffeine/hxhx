/** Activates one feature while leaving the feature-gated update uncalled. */
class Main {
	static function main():Void {
		final value = new FeatureGate(3);
		Sys.println("value=" + value.read());
	}
}

/** Keeps `gatedUpdate` only when DCE observes the public `read` feature. */
class FeatureGate {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function read():Int {
		return value;
	}

	@:ifFeature("FeatureGate.read")
	public function gatedUpdate():Void {
		value++;
	}
}
