/** Delegation and the return call create a real recursive module group. */
class First {
	public static function accept(value:Token):String {
		return Second.accept(value);
	}

	public static function maybe(value:Null<Token>):String {
		return value == null ? "null" : read(value);
	}

	/** Nullable results retain the same variant payload through both module exports. */
	public static function nullable(value:Null<Token>):Null<Token> {
		return Second.nullable(value);
	}

	public static function nullableIdentity(value:Null<Token>):Null<Token> {
		return value;
	}

	public static function optional(?value:Token):String {
		return maybe(value);
	}

	public static function read(value:Token):String {
		return switch (value) {
			case Label(text): text;
			case Items(values): values.join(",");
		};
	}
}
