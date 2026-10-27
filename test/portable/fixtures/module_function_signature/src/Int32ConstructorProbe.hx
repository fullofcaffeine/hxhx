/** A transparent alias must keep the standard Int32 declaration carrier. */
typedef Word = haxe.Int32;

/** Retains existing integer carriers without optimizing abstract calls or storage. */
class Int32ConstructorProbe {
	public final high:haxe.Int32;
	public final low:Word;

	public function new(high:haxe.Int32, low:Word) {
		this.high = high;
		this.low = low;
	}

	public static function retain(value:Word):Word
		return value;
}
