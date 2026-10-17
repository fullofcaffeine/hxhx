/** Captured generic methods retain argument omission and declared defaults. */
class FeatureBoundOptional {
	static function main():Void {
		final receiver = new OptionalReceiver();
		final echo = receiver.echo;
		final alias = echo;
		trace(alias("first"));
		trace(echo("second", 2));
		trace(echo("third", null));
		final optional = receiver.optional;
		trace(optional(7));
		trace(optional(9, "tag"));
	}
}

/** Generic inference and omission flags are independent parts of the same callable contract. */
class OptionalReceiver {
	public function new() {}

	public function echo<T>(value:T, count:Int = 1):T {
		trace(count);
		return value;
	}

	public function optional<T>(value:T, ?tag:String):T {
		trace(tag == null);
		return value;
	}
}
