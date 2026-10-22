/** Written callback types and call-argument contexts constrain the selected capture. */
class FeatureBoundExpected {
	static function consume(callback:String->String):Void {
		trace(callback("argument"));
	}

	static function main():Void {
		final receiver = new ExpectedReceiver<String>();
		final text:String->String = receiver.echo;
		final alias = text;
		trace(alias("written"));
		consume(receiver.echo);
		final mixed:String->Int->Int = receiver.choose;
		trace(mixed("class", 9));
	}
}

/** Class and method parameters have distinct identities even when used in one signature. */
class ExpectedReceiver<T> {
	public function new() {}

	public function echo<U>(value:U):U {
		return value;
	}

	public function choose<U>(label:T, value:U):U {
		trace(label);
		return value;
	}
}
