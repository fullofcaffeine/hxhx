/** Typing-only fixture: every handler deliberately ignores its caught value. */
class Main {
	static function statement():Void {
		try {
			throw "text";
		} catch (unused:String) {}
	}

	static function expression():Int {
		return try 1 catch (unused:Int) 2;
	}

	static function base():Void {
		try {
			throw 1;
		} catch (unused:haxe.Exception) {}
	}

	static function raw():Void {
		try {
			throw 1;
		} catch (unused:Dynamic) {}
	}

	static function subtype():Void {
		try {
			throw 1;
		} catch (unused:Child) {}
	}
}

class Child extends haxe.Exception {}
