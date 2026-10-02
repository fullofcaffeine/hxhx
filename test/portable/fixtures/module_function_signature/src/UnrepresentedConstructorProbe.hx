/** Two constructor arguments are outside the current checked constructor-signature slice. */
class UnrepresentedConstructorProbe {
	public final seed:Int;

	public function new(seed:Int, offset:Int) {
		this.seed = seed + offset;
	}
}
