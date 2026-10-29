/** The same authored declaration is tested as an SDK provider and as a project override. */
class FeatureOriginLibrary {
	public static function used():Void {
		trace("used");
	}

	public static function unused():Void {
		untyped __define_feature__("origin.library", true);
	}
}
