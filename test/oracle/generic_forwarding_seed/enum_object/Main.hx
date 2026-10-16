/** An ordinary class cannot satisfy EnumValue through a nominal name or object representation. */
class Main {
	static function requireEnum<T:EnumValue>(value:T):T {
		return value;
	}

	static function forward<U:Entry>(value:U):U {
		return requireEnum(value);
	}

	static function main():Void {}
}

/** This class deliberately shares the positive fixture's enum name. */
class Entry {
	public function new() {}
}
