package;

/** A nominal value without a source `toString` method. */
class DynamicStringBox {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}
