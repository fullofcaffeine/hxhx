/** Reference traversal must distinguish feature-gated calls from ordinary calls and method values. */
class FeatureReferences {
	static function hidden():Void {
		untyped __define_feature__("reference.hidden", true);
		trace("wrong:hidden");
	}

	static function relay():Void {
		leaf();
	}

	static function leaf():Void {
		untyped __define_feature__("reference.leaf", true);
	}

	static function callback():Void {
		untyped __define_feature__("reference.callback", true);
		trace("wrong:callback");
	}

	static function main():Void {
		untyped __feature__("reference.hidden", trace("hidden:on"), trace("hidden:off"));
		untyped __feature__("reference.leaf", trace("leaf:on"), trace("leaf:off"));
		untyped __feature__("reference.callback", trace("callback:on"), trace("callback:off"));
		untyped __feature__("reference.absent", hidden());
		relay();
		final selected = callback;
		trace(selected != null);
	}
}
