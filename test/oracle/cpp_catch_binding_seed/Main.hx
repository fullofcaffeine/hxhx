/** Catch annotations select real implicit providers even when no handler reads its binding. */
class Main {
	static function main():Void {
		try {
			throw "problem";
		} catch (number:Int) {
			throw "wrong numeric handler";
		} catch (text:String) {
			if (text != "problem")
				throw "lost string value";
		} catch (any:Dynamic) {
			throw "wrong fallback handler";
		}
		try {
			throw "wrapped";
		} catch (wrapped:haxe.ValueException) {
			if (wrapped.value != "wrapped")
				throw "lost string wrapper payload";
		} catch (fallback:Dynamic) {
			throw "string did not match ValueException";
		}
		try {
			throw "converted";
		} catch (exception) {
			if (exception.message != "converted")
				throw "lost implicit conversion";
		}
	}
}
