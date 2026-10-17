/** Constants coexist with a mutual record-type dependency, without value recursion. */
class TypeLeft {
	public static final tag:String = "left";

	public var other:Null<TypeRight>;

	public function new() {}
}
