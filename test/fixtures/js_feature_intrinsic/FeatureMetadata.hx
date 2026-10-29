/** Retention metadata and static initialization can expose features without a normal call. */
class FeatureMetadata {
	static var unusedEffect:Bool = initialize();

	static function initialize():Bool {
		untyped __define_feature__("metadata.effect", true);
		trace("field:effect");
		return true;
	}

	static function main():Void {
		untyped __feature__("metadata.effect", trace("effect:on"), trace("effect:off"));
		untyped __feature__("metadata.init", trace("init:on"), trace("init:off"));
		untyped __feature__("metadata.init-method", trace("init-method:on"), trace("init-method:off"));
		untyped __feature__("metadata.sub", trace("sub:on"), trace("sub:off"));
		untyped __feature__("metadata.base", trace("base:on"), trace("base:off"));
		untyped __feature__("metadata.exposed", trace("exposed:on"), trace("exposed:off"));
		untyped __feature__("metadata.private", trace("private:on"), trace("private:off"));
		untyped __feature__("MetadataInit.*", trace("init-class:on"), trace("init-class:off"));
	}
}

/** Keep initialization separately from unused methods. */
@:keepInit
class MetadataInit {
	static function __init__():Void {
		untyped __define_feature__("metadata.init", true);
	}

	static function unused():Void {
		untyped __define_feature__("metadata.init-method", true);
	}
}

/** Keep-sub metadata starts an inheritance retention contract. */
@:keepSub
class MetadataBase {
	public function unused():Void {
		untyped __define_feature__("metadata.base", true);
	}
}

/** The subclass is loaded but never constructed or named as a value. */
class MetadataSub extends MetadataBase {
	public function added():Void {
		untyped __define_feature__("metadata.sub", true);
	}
}

/** Exported class retention distinguishes public and private methods. */
@:expose
class MetadataExposed {
	public static function visible():Void {
		untyped __define_feature__("metadata.exposed", true);
	}

	static function hidden():Void {
		untyped __define_feature__("metadata.private", true);
	}
}
