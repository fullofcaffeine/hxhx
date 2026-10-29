/** Observe typed Int remainder without constant-folding the operands. */
class Main {
	static function observe(label:String, left:Int, right:Int):Void {
		try {
			final result:Int = left % right;
			Sys.println(label + ":" + result);
		} catch (error:haxe.Exception) {
			Sys.println(label + ":throw:" + error.message);
		}
	}

	static function main():Void {
		observe("positive", 7, 3);
		observe("negative-left", -7, 3);
		observe("negative-right", 7, -3);
		observe("negative-both", -7, -3);
		observe("minimum-negative-one", -2147483648, -1);
		observe("zero-divisor", 7, 0);
		observe("zero-zero", 0, 0);
	}
}
