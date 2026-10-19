/** Exercises Haxe's nullable-to-enum return compatibility through a public method. */
class Projection {
	final holder:Holder;

	public function new(holder:Holder) {
		this.holder = holder;
	}

	public function get():Choice {
		return Holder.read(holder);
	}
}
