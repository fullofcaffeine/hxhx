/** Retains two declaration arguments outside the optimized constructor-call subset. */
class ConstructorProbe {
	public final seed:Int;

	public function new(seed:Int, offset:Int) {
		this.seed = seed + offset;
	}
}
