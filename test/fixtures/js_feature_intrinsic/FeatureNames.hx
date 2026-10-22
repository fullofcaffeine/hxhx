/** Feature protocol names for secondary types must come from observed compiler behavior. */
class FeatureNames {
	static function main():Void {
		untyped __feature__("FeatureNames.Secondary.touch", trace("module:on"), trace("module:off"));
		untyped __feature__("Secondary.touch", trace("short:on"), trace("short:off"));
		untyped __feature__("FeatureNames.Secondary.*", trace("module-class:on"), trace("module-class:off"));
		untyped __feature__("Secondary.*", trace("short-class:on"), trace("short-class:off"));
		Secondary.touch();
	}
}

class Secondary {
	public static function touch():Void {
		trace("touch");
	}
}
