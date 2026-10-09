/** Observe the first authored failure without requiring native typed-catch support. */
class Upstream {
	static function main():Void {
		try {
			Main.run();
		} catch (value:String) {
			if (value != "initializer")
				throw "inherited initializer did not fail first";
			return;
		}
		throw "inherited initializer failure was omitted";
	}
}
