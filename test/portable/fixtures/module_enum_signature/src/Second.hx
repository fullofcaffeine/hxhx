/** Returns through the other module without replacing the enum payload. */
class Second {
	public static function accept(value:Token):String {
		return First.read(value);
	}

	public static function nullable(value:Null<Token>):Null<Token> {
		return First.nullableIdentity(value);
	}
}
