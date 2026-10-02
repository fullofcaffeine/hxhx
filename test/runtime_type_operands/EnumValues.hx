import left.Parent;

/** A same-module enum constructor keeps ordinary value lookup precedence. */
class EnumValues {
	public static function read():Token {
		return Parent;
	}
}

enum Token {
	Parent;
}
