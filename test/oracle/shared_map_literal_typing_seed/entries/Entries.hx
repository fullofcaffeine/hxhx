import haxe.ds.Map;

/** Nonempty literals retain destination storage while each operand keeps its source type. */
class Entries {
	public static var field:Map<String, Dynamic> = ["value" => true];

	public static function returned(value:Float):Map<String, Dynamic>
		return ["value" => value];

	public static function local(value:Float):Map<String, Dynamic> {
		final result:Map<String, Dynamic> = ["value" => value];
		return result;
	}

	public static function assigned(result:Map<String, Dynamic>, value:Float):Map<String, Dynamic> {
		result = ["value" => value];
		return result;
	}

	static function take(value:Map<String, Dynamic>):Map<String, Dynamic>
		return value;

	public static function argument(value:Float):Map<String, Dynamic>
		return take(["value" => value]);

	public static function nested(value:Bool):Map<String, {item:Dynamic}>
		return ["value" => {item: value}];

	public static function generic<V>(value:V):Map<String, V>
		return ["value" => value];

	public static function callback():Map<String, Bool->Bool>
		return ["value" => value -> value];

	public static function mixed():Map<String, Dynamic>
		return ["boolean" => true, "text" => "ok"];

	public static function ordinary(value:Float):Array<Float>
		return [value];
}
