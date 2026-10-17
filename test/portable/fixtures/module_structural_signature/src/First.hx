/** A record passed across mutually dependent modules without changing its identity. */
typedef Item = {
	var value:Int;
	var ?label:String;
};

/** The recursive group must export the same carrier used by these function bodies. */
class First {
	/** Nullable records keep the same reference across both recursive modules. */
	public static function maybe(item:Item, present:Bool):Null<Item> {
		return Second.maybe(item, present);
	}

	public static function hold(?item:Item):RecordHolder {
		return new RecordHolder(item);
	}

	public static function floatIdentity(value:Float):Float {
		return Second.floatIdentity(value);
	}

	public static function copy(item:Item):Item {
		return Second.copy(item);
	}

	public static function make(value:Int):Item {
		return {value: value};
	}

	public static function change(item:Item, value:Int):Void {
		item.value = value;
	}

	public static function withToken(item:Item, token:Token):Item {
		return make(item.value + token.values[0]);
	}

	/** Omitted and explicit null inputs allocate a group; supplied arrays keep their identity. */
	public static function scopes(item:Item, ?groups:Array<Array<Token>>):Array<Array<Token>> {
		return groups == null ? [[new Token(item.value)]] : Second.scopes(groups);
	}

	public static function identity(groups:Array<Array<Token>>):Array<Array<Token>> {
		return groups;
	}
}
