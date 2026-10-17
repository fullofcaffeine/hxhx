/** Owns shared mutable state observed through a base-class reference. */
class Base extends Root {
	public var count:Int;

	public function new(count:Int) {
		super();
		this.count = count;
	}

	public function describe():String {
		return First.label("base", count);
	}
}
