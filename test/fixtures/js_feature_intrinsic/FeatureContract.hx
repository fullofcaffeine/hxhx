/** Black-box observations distinguish compilation reachability from runtime branch evaluation. */
class FeatureContract {
	static function unused():Void {
		untyped __define_feature__("probe.unused", true);
	}

	static function active():Void {
		trace("active:called");
	}

	static function main():Void {
		untyped __feature__("probe.late", trace("late:on"), trace("late:off"));
		untyped __define_feature__("probe.late", trace("define:effect"));
		untyped __feature__("probe.absent", trace("absent:on"), trace("absent:off"));
		untyped __feature__("probe.unused", trace("unused:on"), trace("unused:off"));
		untyped __feature__("FeatureContract.active", trace("method:on"), trace("method:off"));
		untyped __feature__("FeatureContract.*", trace("class:on"), trace("class:off"));
		final value:String = untyped __feature__("probe.late", {
			trace("value:effect");
			"selected";
		}, "fallback");
		trace(value);
		final definition:String = untyped __define_feature__("probe.value", "definition-value");
		trace(definition);
		untyped __feature__("probe.value", trace("value:on"));
		untyped __feature__("probe.missing.two", trace("wrong:two"));
		active();
	}
}
