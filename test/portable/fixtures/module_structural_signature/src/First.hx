/** A record passed across mutually dependent modules without changing its identity. */
typedef Item = {
	var value:Int;
	var ?label:String;
};

/** The recursive group must export the same carrier used by these function bodies. */
class First {
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
}
