/** A declared iterator result keeps its structural type distinct from its public typedef spelling. */
class TypedPairProducer {
	public static function make():Iterator<{key:String, value:Int}> {
		return [{key: "entry", value: 1}].iterator();
	}
}
