/** Exercises a zero-argument super-constructor inside the recursive module group. */
class Root {
	public function new() {}

	public function marker():String {
		return First.label("root", 0);
	}
}
