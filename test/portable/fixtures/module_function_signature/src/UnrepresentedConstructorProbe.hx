/** Array parameters still require a checked private runtime signature. */
class UnrepresentedConstructorProbe {
	public final seed:Int;

	public function new(seed:Int, offsets:Array<Int>) {
		this.seed = seed + offsets[0];
	}
}
