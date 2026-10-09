/** Observe the same exception with upstream Haxe without requiring local typed-catch support. */
class Upstream {
	static function main():Void {
		var caught = false;
		try
			Main.run()
		catch (message:String) {
			if (message != "selected operand")
				throw message;
			caught = true;
		}
		if (!caught)
			throw "selected logical operand did not throw";
	}
}
