/** Parent/interface calls select implementations without executing every candidate body. */
class FeatureDispatch {
	static function main():Void {
		untyped __feature__("dispatch.parent", trace("parent:on"), trace("parent:off"));
		untyped __feature__("dispatch.child", trace("child:on"), trace("child:off"));
		untyped __feature__("dispatch.class-only", trace("class-only:on"), trace("class-only:off"));
		untyped __feature__("dispatch.unused", trace("unused:on"), trace("unused:off"));
		untyped __feature__("dispatch.interface", trace("interface:on"), trace("interface:off"));
		untyped __feature__("dispatch.unrelated", trace("unrelated:on"), trace("unrelated:off"));
		untyped __feature__("dispatch.follow", trace("follow:on"), trace("follow:off"));
		final receiver:DispatchParent = new DispatchChild();
		receiver.run();
		final via:DispatchApi = new DispatchImplementation();
		via.run();
		final classOnly = DispatchClassOnly;
		trace(classOnly != null);
		final unrelated = DispatchUnrelated;
		trace(unrelated != null);
	}
}

/** The selected declaration is separate from the implementation reached at runtime. */
class DispatchParent {
	public function new() {}

	public function run():Void {
		untyped __define_feature__("dispatch.parent", true);
		trace("wrong:parent");
	}
}

/** Constructed overriding receiver. */
class DispatchChild extends DispatchParent {
	public function new() {
		super();
	}

	override public function run():Void {
		untyped __define_feature__("dispatch.child", true);
		DispatchFollow.touch();
		trace("child:called");
	}
}

/** A retained class object need not imply construction. */
class DispatchClassOnly extends DispatchParent {
	override public function run():Void {
		untyped __define_feature__("dispatch.class-only", true);
		trace("wrong:class-only");
	}
}

/** An unrelated loaded subclass tests whether traversal retains too much. */
class DispatchUnused extends DispatchParent {
	override public function run():Void {
		untyped __define_feature__("dispatch.unused", true);
		trace("wrong:unused");
	}
}

/** Interface dispatch has no executable declaration body. */
interface DispatchApi {
	public function run():Void;
}

/** Concrete implementation contributes a feature only through retention or dispatch. */
class DispatchImplementation implements DispatchApi {
	public function new() {}

	public function run():Void {
		untyped __define_feature__("dispatch.interface", true);
		trace("interface:called");
	}
}

/** A retained unrelated type must not match a virtual member only by spelling. */
class DispatchUnrelated {
	public function run():Void {
		untyped __define_feature__("dispatch.unrelated", true);
		trace("wrong:unrelated");
	}
}

/** This reference appears only after retaining an override implementation. */
class DispatchFollow {
	public static function touch():Void {
		untyped __define_feature__("dispatch.follow", true);
	}
}
