/** Probe an unsupported value use: upstream 4.3.7 emits invalid JavaScript for this absent branch. */
class FeatureAbsentValue {
	static function main():Void {
		final value:Dynamic = untyped __feature__("probe.absent.value", "present");
		trace(value);
	}
}
