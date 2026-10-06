/** A richer record joins the recursive group without admitting array field optimizations. */
class Token {
	public final value:Int;
	public final values:Array<Int>;

	public function new(value:Int) {
		this.value = value;
		this.values = [First.make(value).value];
	}
}
