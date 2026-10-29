/** Observe when ordinary trace selects its replaceable logging function. */
class TraceOrder {
	static function main():Void {
		final original = haxe.Log.trace;
		haxe.Log.trace = function(value:Dynamic, ?position:haxe.PosInfos):Void {
			original("first:" + value, null);
		};
		trace({
			haxe.Log.trace = function(value:Dynamic, ?position:haxe.PosInfos):Void {
				original("second:" + value, null);
			};
			"value";
		});
		trace("next", "extra");
		original("done", null);
	}
}
