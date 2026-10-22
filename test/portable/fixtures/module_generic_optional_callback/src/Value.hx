/** Object identity and array mutation must survive the generic callback result. */
class Value {
	public final items:Array<Int>;

	public function new(items:Array<Int>) {
		this.items = items;
	}
}
