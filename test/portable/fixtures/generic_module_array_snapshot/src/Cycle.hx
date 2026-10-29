/** Forces Snapshot into a recursive module group with this declaration. */
class Cycle {
	public static function depth(n:Int):Int {
		return n == 0 ? 0 : Snapshot.depth(n - 1) + 1;
	}
}
