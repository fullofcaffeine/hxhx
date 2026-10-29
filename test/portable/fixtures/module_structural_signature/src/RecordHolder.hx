import First.Item;

/** An omitted record argument selects a value through the same recursive group. */
class RecordHolder {
	public final item:Item;

	public function new(?item:Item) {
		this.item = item == null ? First.make(5) : item;
	}
}
