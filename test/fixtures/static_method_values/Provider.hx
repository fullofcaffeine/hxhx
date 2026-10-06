/** First provider deliberately shares its method name with another provider. */
class Provider {
	public static function choose(value:Int):Int {
		return value;
	}
}
