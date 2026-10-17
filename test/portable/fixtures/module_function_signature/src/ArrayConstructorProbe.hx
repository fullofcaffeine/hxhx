/** An array argument has a checked export type even when its module needs no interface. */
class ArrayConstructorProbe {
	public final seed:Int;

	public function new(seed:Int, offsets:Array<Int>) {
		this.seed = seed + offsets[0];
	}
}
