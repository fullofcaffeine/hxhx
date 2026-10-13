/** The back-reference requires a real OCaml recursive module signature. */
class Right {
	public static function value(n:Int):Int {
		return n == 0 ? 0 : Left.value(n - 1) + 1;
	}
}
