/** Distinguish initialization and explicit retention from ordinary method reachability. */
class FeatureRetention {
	static var unusedField:Bool = untyped __define_feature__("retention.field", true);

	static function __init__():Void {
		untyped __define_feature__("retention.init", true);
	}

	@:keep
	static function kept():Void {
		untyped __define_feature__("retention.kept", true);
	}

	static function unused():Void {
		untyped __define_feature__("retention.unused", true);
	}

	static function main():Void {
		untyped __feature__("retention.init", trace("init:on"), trace("init:off"));
		untyped __feature__("retention.kept", trace("kept:on"), trace("kept:off"));
		untyped __feature__("retention.field", trace("field:on"), trace("field:off"));
		untyped __feature__("retention.unused", trace("unused:on"), trace("unused:off"));
		untyped __feature__("retention.kept-class", trace("kept-class:on"), trace("kept-class:off"));
		untyped __feature__("retention.unused-class", trace("unused-class:on"), trace("unused-class:off"));
		untyped __feature__("retention.unused-init", trace("unused-init:on"), trace("unused-init:off"));
	}
}

/** Explicit class retention includes an otherwise unused method. */
@:keep
class RetentionKept {
	static function unused():Void {
		untyped __define_feature__("retention.kept-class", true);
	}
}

/** Sharing a loaded source module does not by itself prove runtime reachability. */
class RetentionUnused {
	static function __init__():Void {
		untyped __define_feature__("retention.unused-init", true);
	}

	static function unused():Void {
		untyped __define_feature__("retention.unused-class", true);
	}
}
