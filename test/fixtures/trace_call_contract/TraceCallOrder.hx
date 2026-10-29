/** Compare an ordinary call operand with the statement-valued trace operand. */
class TraceCallOrder {
	static function main():Void {
		final original = haxe.Log.trace;
		haxe.Log.trace = function(value:Dynamic, ?position:haxe.PosInfos):Void original("first:" + value, null);
		function replace():String {
			haxe.Log.trace = function(value:Dynamic, ?position:haxe.PosInfos):Void original("second:" + value, null);
			return "value";
		}
		trace(replace());
		trace("next");
	}
}
