/** An absent field becomes present only when the authored assignment executes. */
typedef OptionalRecord = {var ?item:Dynamic;}

/** Ordinary field writes preserve aliases and return the assigned value. */
class RecordWrite {
	public static function assign(receiver:Void->{item: Dynamic}, value:Void->Bool):Dynamic
		return receiver().item = value();

	public static function discard(receiver:Void->{item: Dynamic}, value:Void->Bool):Void {
		receiver().item = value();
	}

	public static function text(receiver:Void->{item: String}, value:Void->String):String
		return receiver().item = value();

	public static function nested(receiver:Void->{inner: {item: String}}, value:Void->String):String
		return receiver().inner.item = value();

	public static function object(receiver:Void->{item: {name: String}}, value:Void->{name: String}):{name:String}
		return receiver().item = value();

	public static function optional(receiver:Void->OptionalRecord, value:Void->Bool):Dynamic
		return receiver().item = value();

	public static function local(value:Bool):Dynamic {
		final record:{item:Dynamic} = {item: null};
		final alias = record;
		record.item = value;
		return alias.item;
	}
}
