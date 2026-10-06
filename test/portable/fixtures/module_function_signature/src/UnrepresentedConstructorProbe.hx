/** Function parameters remain outside the supported declaration-signature family. */
class UnrepresentedConstructorProbe {
	public final seed:Int;

	public function new(seed:Int, adjust:Int->Int) {
		this.seed = adjust(seed);
	}
}
