/** A concrete enum bound proves EnumValue while preserving the caller's exact type. */
class Main {
	static function requireEnum<T:EnumValue>(value:T):T {
		return value;
	}

	static function forward<U:Entry>(value:U):U {
		return requireEnum(value);
	}

	static function read(value:Entry):Int {
		return switch value {
			case Empty: 0;
			case Value(number): number;
		};
	}

	static function main():Void {
		Sys.println(read(requireEnum(Entry.Value(7))));
		Sys.println(read(forward(Entry.Empty)));
	}
}

/** Both singleton and payload values satisfy the same core EnumValue bound. */
enum Entry {
	Empty;
	Value(number:Int);
}
