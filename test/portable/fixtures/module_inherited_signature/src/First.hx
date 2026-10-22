/** Exports base-class values through a recursive module group. */
class First {
	public static function child(value:Child):Child {
		return Second.child(value);
	}

	public static function label(name:String, count:Int):String {
		return name + ":" + count;
	}

	public static function observe(value:Base):String {
		return Second.observe(value);
	}

	public static function read(value:Base):String {
		return value.describe();
	}

	public static function retain(value:Base):Base {
		return Second.retain(value);
	}

	public static function identity(value:Base):Base {
		return value;
	}

	public static function maybe(value:Null<Base>):String {
		return value == null ? "null" : observe(value);
	}
}
