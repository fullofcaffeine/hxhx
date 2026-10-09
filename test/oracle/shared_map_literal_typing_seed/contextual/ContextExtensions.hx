import haxe.ds.Map;

/** Extension receivers supply the first declared argument, including generic evidence. */
class ContextExtensions {
	public static function takeContext(witness:String, values:Map<Int, String>):Bool
		return values.exists(1);

	public static function takeGenericContext<V>(witness:V, values:Map<String, V>):Bool
		return values.exists("one");
}
