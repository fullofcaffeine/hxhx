/** Independently observe Haxe's constructor-versus-initializer failure ordering. */
class Upstream {
	static function main():Void {
		try {
			Main.run();
		} catch (value:String) {
			if (value != "initializer")
				throw "wrong construction failure: " + value;
			Sys.println(value);
			return;
		}
		throw "construction did not throw";
	}
}
