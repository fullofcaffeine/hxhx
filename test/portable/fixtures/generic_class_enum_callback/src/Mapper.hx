/** Supplies the generic class-method callback boundary used by the bootstrap. */
class Mapper<T> {
	final items:Array<T>;

	public function new(items:Array<T>) {
		this.items = items;
	}

	public function apply(transform:T->T):Array<T> {
		var changed:Null<Array<T>> = null;
		for (index in 0...items.length) {
			final original = items[index];
			final mapped = transform(original);
			if (changed == null && mapped != original)
				changed = items.copy();
			if (changed != null)
				changed[index] = mapped;
		}
		return changed == null ? items : changed;
	}
}
