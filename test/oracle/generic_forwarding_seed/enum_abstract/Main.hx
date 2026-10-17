/** An enum abstract retains its backing value and cannot supply an ordinary enum value. */
class Main {
	static function requireEnum<T:EnumValue>(value:T):T {
		return value;
	}

	static function forward<U:Entry>(value:U):U {
		return requireEnum(value);
	}

	static function main():Void {}
}

/** Closed integer values are not heap enum constructors. */
enum abstract Entry(Int) {
	var Value = 1;
}
