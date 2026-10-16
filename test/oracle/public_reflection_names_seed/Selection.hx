import model.Types.PublicLeaf as Left;
import other.Types.PublicLeaf as Right;

/** Alias lookup and local shadowing must preserve the selected declaration. */
class Selection {
	public static function left()
		return Left;

	public static function right()
		return Right;

	public static function shadow(Left:Int):Int
		return Left;
}
