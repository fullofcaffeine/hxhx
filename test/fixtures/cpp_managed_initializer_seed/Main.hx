/** Startup expressions retain exact calls, earlier fields, and aggregate child order. */
class Main {
	public static final first:Int = supply(3);
	public static var second:Int = first + 4;
	public static var record:{value:Int, label:String} = {value: second, label: "startup"};

	public static function supply(value:Int):Int {
		return value + 1;
	}

	public static function firstValue():Int {
		return first;
	}

	public static function current():{value:Int, label:String} {
		return record;
	}

	public static function read():Int {
		return record.value;
	}

	public static function label():String {
		return record.label;
	}
}
