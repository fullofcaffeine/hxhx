/** Establish the result contract independently with upstream Haxe before target adaptation. */
class UpstreamFunctionValuesProbe {
	static function main():Void {
		if (Main.choose(7, 9) != 7 || Main.choose(-3, 11) != -3)
			throw "function result did not preserve the first argument";
		if (!Main.logical(true) || Main.logical(false))
			throw "function result did not preserve its Boolean argument";
		if (Main.text("hé\x00z") != "hé\x00z")
			throw "function result did not preserve its String argument";
		if (Main.invoke(3, 5) != 3 || Main.invoke(-8, 3) != -8 || Main.scoped(8) != 8)
			throw "nested calls or shadowing changed a parameter value";
		Main.done();
	}
}
