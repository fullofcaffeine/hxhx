/** Observe the public position record and ordered custom trace operands. */
class TracePosition {
	static function main():Void {
		final original = haxe.Log.trace;
		haxe.Log.trace = function(value:Dynamic, ?position:haxe.PosInfos):Void {
			original(value
				+ ":"
				+ position.className
				+ ":"
				+ position.methodName
				+ ":"
				+ position.lineNumber
				+ ":"
				+ position.customParams.join("|"), null);
		};
		trace("value", "extra", 7);
	}
}
