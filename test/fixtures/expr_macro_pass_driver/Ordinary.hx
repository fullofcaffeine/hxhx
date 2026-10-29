class Ordinary {
	static function main():Void {
		var text = StringTools.trim(" ordinary ");
		var stack = haxe.CallStack.toString(haxe.CallStack.callStack());
	}
}
