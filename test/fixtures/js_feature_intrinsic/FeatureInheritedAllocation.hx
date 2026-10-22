/** Allocating a child with an inherited constructor must retain its own method implementations. */
class AllocationParent {
	public function new() {}

	public function label():String
		return "parent";
}

class AllocationChild extends AllocationParent {
	public override function label():String {
		untyped __define_feature__("allocation.child", true);
		return "child";
	}
}

class FeatureInheritedAllocation {
	static function main():Void {
		untyped __feature__("allocation.child", trace("child:on"), trace("child:off"));
		final value:AllocationParent = new AllocationChild();
		trace(value.label());
	}
}
