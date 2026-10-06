/** Argument effects precede the failure from invoking a null function value. */
class Main {
	static function main():Void {
		var callback:Int->Int = null;
		var effects = 0;
		try {
			callback(++effects);
		} catch (error:haxe.Exception) {
			Sys.println("caught");
		}
		Sys.println(effects);
	}
}
