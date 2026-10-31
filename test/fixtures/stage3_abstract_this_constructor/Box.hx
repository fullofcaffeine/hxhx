/** A generic abstract in its own module, constructed from `Main`. */
abstract Box<T>(T) {
	public function new(value:T)
		this = value;

	public function unwrap():T
		return this;
}
