package hxhxmacros;

@:syntheticStaticClass
class RuntimeSyntheticStatics {
	@:classLabel
	public static final classLabel = "class-label";

	@:classSummary
	public static function buildTag(prefix:String, count:Int):String {
		return prefix + ":" + count;
	}
}

@:syntheticStaticAbstract
abstract RuntimeSyntheticAbstract(String) from String to String {
	@:abstractLabel
	public static final abstractLabel = "abstract-label";

	@:abstractSummary
	public static function renderTag(prefix:String, enabled:Bool):String {
		return enabled ? prefix : (prefix + "-off");
	}
}
