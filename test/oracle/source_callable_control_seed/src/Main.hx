/** A callback used inside a source function keeps the same argument and result contract. */
class Main {
	static function invoke(callback:Dynamic):Int {
		var read:Void->Int = function():Int {
			var result:Int = callback(7);
			return result;
		};
		return read();
	}

	static function main():Void {
		Sys.println(invoke(function(value:Int):Int {
			return value + 3;
		}));
	}
}
