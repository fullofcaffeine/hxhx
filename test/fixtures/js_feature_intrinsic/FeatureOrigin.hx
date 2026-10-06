/** Compare feature activation for project and SDK declarations, with and without a call. */
class FeatureOrigin {
	static function main():Void {
		untyped __feature__("origin.library", trace("library:on"), trace("library:off"));
		FeatureOriginLibrary.used();
		#if feature_origin_call
		FeatureOriginLibrary.unused();
		#end
	}
}
