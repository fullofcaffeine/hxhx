/**
	Effect-only direct static calls used by the portable call-plan contract.

	The methods deliberately return no Haxe value. Their observable output lets
	the fixture prove that argument evaluation and the invocation each happen
	exactly once.
**/
class VoidCalls {
	public static function noArguments():Void {
		Sys.println("void-zero-callee");
	}

	public static function withArguments(count:Int, enabled:Bool, label:String):Void {
		Sys.println('void-callee=$count,$enabled,$label');
	}
}
