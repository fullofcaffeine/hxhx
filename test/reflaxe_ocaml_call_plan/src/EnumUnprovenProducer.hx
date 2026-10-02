/** Negative input: an enum annotation cannot prove a native enum result. */
class EnumUnprovenProducer {
	public static function unproven(value:Dynamic):PreliminaryCallFactsEnum {
		// This unchecked cast is deliberate compiler-test input. Never execute it.
		return cast value;
	}
}
