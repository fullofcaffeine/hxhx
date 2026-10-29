/** Replacing a dynamic method retains both declarations but executes only the replacement. */
class FeatureDynamic {
	static function replacement():Void {
		untyped __define_feature__("dynamic.replacement", true);
		trace("replacement:called");
	}

	static function main():Void {
		untyped __feature__("dynamic.original", trace("original:on"), trace("original:off"));
		untyped __feature__("dynamic.replacement", trace("replacement:on"), trace("replacement:off"));
		final receiver = new DynamicReceiver();
		receiver.run = replacement;
		receiver.run();
	}
}

/** The original method remains a possible class member despite this instance's replacement. */
class DynamicReceiver {
	public function new() {}

	public dynamic function run():Void {
		untyped __define_feature__("dynamic.original", true);
		trace("wrong:original");
	}
}
