/** Keeps the generic map helper in a recursive module group. */
class Right {
	public static function value(n:Int):Int {
		return n == 0 ? 0 : Left.value(n - 1) + 1;
	}
}
