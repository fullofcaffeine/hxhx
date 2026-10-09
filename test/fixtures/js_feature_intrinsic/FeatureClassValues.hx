/** Class objects retain their initialization and inheritance without executing instance methods. */
class FeatureClassValues {
	static function main():Void {
		untyped __feature__("ClassChild.*", trace("child:on"), trace("child:off"));
		untyped __feature__("ClassParent.*", trace("parent:on"), trace("parent:off"));
		untyped __feature__("ClassMarker.*", trace("interface:on"), trace("interface:off"));
		untyped __feature__("class.child-init", trace("child-init:on"), trace("child-init:off"));
		untyped __feature__("class.parent-init", trace("parent-init:on"), trace("parent-init:off"));
		untyped __feature__("class.unused", trace("unused:on"), trace("unused:off"));
		final selected = ClassChild;
		trace(selected != null);
	}
}

/** Parent initialization is distinct from retaining its unused instance method. */
class ClassParent {
	static function __init__():Void {
		untyped __define_feature__("class.parent-init", true);
	}

	public function unused():Void {
		untyped __define_feature__("class.unused", true);
		trace("wrong:instance");
	}
}

/** The class object selects an exact inherited provider and implemented interface. */
class ClassChild extends ClassParent implements ClassMarker {
	static function __init__():Void {
		untyped __define_feature__("class.child-init", true);
	}
}

/** Empty marker identity must survive when the selected class implements it. */
interface ClassMarker {}
