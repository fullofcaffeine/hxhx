/** Constants coexist with a mutual record-type dependency, without value recursion. */
class TypeRight {
	public static final tag:String = "right";

	public var other:Null<TypeLeft>;

	public function new() {}
}
