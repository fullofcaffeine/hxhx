/** Keeps a real function dependency cycle without eager initialization. */
class Right {
	public static function value(n:Int):Int {
		return n == 0 ? 0 : Left.value(n - 1) + 1;
	}
}
