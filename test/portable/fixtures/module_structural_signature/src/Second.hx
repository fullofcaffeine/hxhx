import First.Item;
import First.Entry;

/** Cross-module calls create a cycle, while all module initialization remains delayed. */
class Second {
	public static function entries(values:Array<Entry>):Array<Entry> {
		if (values.length > 0)
			values[0] = First.entry(values[0], true);
		return values;
	}

	public static function maybe(item:Item, present:Bool):Null<Item> {
		return present ? item : null;
	}

	public static function floatIdentity(value:Float):Float {
		return value;
	}

	public static function copy(item:Item):Item {
		return First.make(item.value);
	}

	public static function update(item:Item):Item {
		First.change(item, 9);
		return item;
	}

	public static function scopes(groups:Array<Array<Token>>):Array<Array<Token>> {
		return First.identity(groups);
	}
}
