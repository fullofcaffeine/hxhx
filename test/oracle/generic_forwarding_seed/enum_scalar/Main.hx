/** An integer bound cannot supply an enum value. */
class Main {
	static function requireEnum<T:EnumValue>(value:T):T {
		return value;
	}

	static function forward<U:Int>(value:U):U {
		return requireEnum(value);
	}

	static function main():Void {}
}
