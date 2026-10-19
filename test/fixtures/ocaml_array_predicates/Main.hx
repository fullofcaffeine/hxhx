/** A length field must not make an ordinary object pass an Array predicate. */
class Item {
	public var length:Int = 0;

	public function new() {}
}

/** Array predicates observe runtime identity without examining element storage. */
class Main {
	static function produced():Array<Int> {
		Sys.println("produce");
		return [7];
	}

	static function main():Void {
		final values = [1, 2];
		Sys.println(Std.isOfType(values, Array));
		final dynamicValues:Dynamic = values;
		Sys.println(Std.isOfType(dynamicValues, Array));
		values.push(3);
		Sys.println(Std.isOfType(dynamicValues, Array));
		final empty:Array<Int> = [];
		Sys.println(Std.isOfType(empty, Array));
		Sys.println(Std.isOfType(null, Array));
		Sys.println(Std.isOfType(1, Array));
		Sys.println(Std.isOfType(true, Array));
		Sys.println(Std.isOfType("text", Array));
		Sys.println(Std.isOfType({length: 0}, Array));
		Sys.println(Std.isOfType(new Item(), Array));
		Sys.println(Std.isOfType(produced(), Array));
	}
}
