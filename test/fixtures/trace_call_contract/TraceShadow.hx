/** Observe whether a same-named local shadows the trace language form. */
class TraceShadow {
	static function main():Void {
		final original = haxe.Log.trace;
		final trace = function(value:String):Void original("local:" + value, null);
		trace({original("argument", null); "value";});
	}
}
