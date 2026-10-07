/** Previously unsupported callback parameters now retain their checked function type. */
class UnrepresentedConstructorProbe {
	public final seed:Int;

	public function new(seed:Int, adjust:Int->Int) {
		this.seed = adjust(seed);
	}
}
