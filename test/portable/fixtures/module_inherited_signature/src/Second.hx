/** Returns to First so inherited-class exports require explicit signatures. */
class Second {
	public static function child(value:Child):Child {
		return value;
	}

	public static function observe(value:Base):String {
		return First.read(value);
	}

	public static function retain(value:Base):Base {
		return First.identity(value);
	}
}
