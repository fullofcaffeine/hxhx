/** Dynamic and Any are deliberate inputs: these functions exercise erased comparison itself. */
class Compare {
	public static function equal(left:Dynamic, right:Dynamic):Bool
		return left == right;

	public static function different(left:Dynamic, right:Dynamic):Bool
		return left != right;

	public static function anyEqual(left:Any, right:Any):Bool
		return left == right;

	/** Operand callbacks can allocate or throw. The first result must survive the second call. */
	public static function ordered(left:Void->Dynamic, right:Void->Dynamic):Bool
		return left() == right();
}
