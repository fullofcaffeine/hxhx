/** Black-box observations at Haxe's deliberately heterogeneous throw/catch boundary. */
class Main {
	/** Dynamic is required to observe runtime classification; each input is inspected immediately. */
	static function observe(label:String, value:Dynamic):Void {
		final intType = Std.isOfType(value, Int);
		final floatType = Std.isOfType(value, Float);
		final selected = try {
			throw value;
			"unreachable";
		} catch (_:Int) {
			"int";
		} catch (_:Float) {
			"float";
		} catch (_:Dynamic) {
			"dynamic";
		};
		Sys.println(label + ":" + intType + ":" + floatType + ":" + selected);
	}

	static function main():Void {
		// Construct native floats directly; Math static-field initialization has a separate owner.
		final zero:Float = 0.0;
		observe("integer", 1);
		observe("integral-float", 1.0);
		observe("fraction", 1.5);
		observe("zero", 0.0);
		observe("negative-zero", -0.0);
		observe("nan", (zero / zero));
		observe("positive-infinity", (1.0 / zero));
		observe("negative-infinity", (-1.0 / zero));
		observe("max-31bit-float", 1073741823.0);
		observe("above-31bit-float", 1073741824.0);
		observe("min-31bit-float", -1073741824.0);
		observe("below-31bit-float", -1073741825.0);
		observe("max-int", 2147483647);
		observe("max-int-float", 2147483647.0);
		observe("above-max-int", 2147483648.0);
		observe("min-int", -2147483648);
		observe("min-int-float", -2147483648.0);
		observe("bool", true);
		observe("string", "text");
		observe("null", null);
	}
}
