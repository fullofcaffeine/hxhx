/** Definitions in retained functions are discovered even inside unselected feature branches. */
class FeatureReachability {
	static function conditional(enabled:Bool):Void {
		if (enabled)
			untyped __define_feature__("probe.conditional", trace("wrong:runtime"));
	}

	static function main():Void {
		untyped __feature__("probe.nested", trace("nested:on"), trace("nested:off"));
		untyped __feature__("probe.outer.absent", __define_feature__("probe.nested", trace("wrong:nested")));
		untyped __feature__("probe.fallback", trace("fallback:on"), trace("fallback:off"));
		untyped __feature__("probe.outer.absent", trace("wrong:outer"), __define_feature__("probe.fallback", trace("fallback:effect")));
		untyped __feature__("probe.cycle.a", __define_feature__("probe.cycle.b", trace("cycle:b")));
		untyped __feature__("probe.cycle.b", __define_feature__("probe.cycle.a", trace("cycle:a")));
		untyped __feature__("probe.cycle.a", trace("cycle:on"), trace("cycle:off"));
		untyped __feature__("probe.conditional", trace("conditional:on"), trace("conditional:off"));
		conditional(false);
		untyped __feature__("MissingType.*", trace("missing:on"), trace("missing:off"));
	}
}
