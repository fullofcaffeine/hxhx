package hxhxmacros;

class RuntimeBuildFieldCarrier {
	@:fieldMeta
	public static final answer:Int = 7;

	@:propMeta
	public static var routeTag(default, null):String = "ready";

	@:funMeta
	public static function render(label:String, ?count:Int = 3):String {
		var prefix = label;
		return prefix + ":" + count;
	}
}
