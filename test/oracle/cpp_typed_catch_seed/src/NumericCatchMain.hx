/**
	Observe each primitive catch independently before testing authored handler order.
	Dynamic is intentional at this black-box boundary: each handler must narrow the original runtime value.
	Inputs come from authored literals and public parsing APIs, never from candidate runtime output.
**/
class NumericCatchMain {
	static function acceptsBool(value:Dynamic):Bool {
		try {
			throw value;
		} catch (_:Bool) {
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	static function acceptsInt(value:Dynamic):Bool {
		try {
			throw value;
		} catch (_:Int) {
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	static function acceptsFloat(value:Dynamic):Bool {
		try {
			throw value;
		} catch (_:Float) {
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	static function acceptsString(value:Dynamic):Bool {
		try {
			throw value;
		} catch (_:String) {
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	static function intFirst(value:Dynamic):String {
		try {
			throw value;
		} catch (_:Int) {
			return "int";
		} catch (_:Float) {
			return "float";
		} catch (_:Dynamic) {
			return "other";
		}
	}

	static function floatFirst(value:Dynamic):String {
		try {
			throw value;
		} catch (_:Float) {
			return "float";
		} catch (_:Dynamic) {
			return "other";
		}
	}

	/** A reciprocal observes a zero's sign without depending on target-specific Float formatting. */
	static function floatBinding(value:Dynamic):String {
		try {
			throw value;
		} catch (number:Float) {
			return number == 0 ? (1.0 / number < 0 ? "negative-zero" : "positive-zero") : "nonzero";
		} catch (_:Dynamic) {
			return "other";
		}
	}

	/** Rethrow the narrowed binding, so the next handler observes any conversion performed at binding. */
	static function intRethrow(value:Dynamic):String {
		try {
			try {
				throw value;
			} catch (number:Int) {
				throw number;
			}
		} catch (number:Float) {
			return number == 0 ? (1.0 / number < 0 ? "negative-zero" : "positive-zero") : "nonzero";
		} catch (_:Dynamic) {
			return "other";
		}
	}

	static function bit(value:Bool):String
		return value ? "1" : "0";

	static function observe(name:String, value:Dynamic):Void {
		Sys.println(name + ":" + bit(acceptsBool(value)) + bit(acceptsInt(value)) + bit(acceptsFloat(value)) + bit(acceptsString(value)) + ":"
			+ intFirst(value) + ":" + floatFirst(value) + ":" + floatBinding(value) + ":" + intRethrow(value));
	}

	/** Compare ordinary erasure with throw transport, so a carrier conversion cannot masquerade as a catch conversion. */
	static function observeZeroErasure(value:Float):Void {
		Sys.println("zero-before-erasure=" + (1.0 / value < 0));
		final erased:Dynamic = value;
		if (!Std.isOfType(erased, Float))
			throw "a Float lost numeric compatibility at the Dynamic boundary";
		final restored:Float = erased;
		Sys.println("zero-after-erasure=" + (1.0 / restored < 0));
	}

	static function main():Void {
		observe("true", true);
		observe("false", false);
		observe("int-zero", 0);
		observe("int-one", 1);
		observe("int-min", -2147483647 - 1);
		observe("int-max", 2147483647);
		observe("float-integral", 7.0);
		observe("runtime-integral", Std.parseFloat("7.0"));
		observe("runtime-varying-integral", Std.parseFloat("7.0") + Sys.args().length);
		observe("float-negative-one", -1.0);
		observe("float-negative-two", -2.0);
		observe("float-255", 255.0);
		observe("float-256", 256.0);
		observe("float-257", 257.0);
		observe("float-65535", 65535.0);
		observe("float-65536", 65536.0);
		observe("float-16777215", 16777215.0);
		observe("float-16777216", 16777216.0);
		observe("fraction", 7.5);
		observe("negative-fraction", -7.5);
		observe("float-min", -2147483648.0);
		observe("float-max", 2147483647.0);
		observe("float-min-plus-one", -2147483647.0);
		observe("float-max-minus-one", 2147483646.0);
		observe("float-negative-30-bit", -1073741824.0);
		observe("float-below-negative-30-bit", -1073741825.0);
		observe("float-positive-30-bit", 1073741823.0);
		observe("float-above-positive-30-bit", 1073741824.0);
		observe("below-min", -2147483649.0);
		observe("above-max", 2147483648.0);
		observe("near-min-inside", -2147483647.5);
		observe("near-max-outside", 2147483647.5);
		observe("nan", Math.NaN);
		observe("positive-infinity", Math.POSITIVE_INFINITY);
		observe("negative-infinity", Math.NEGATIVE_INFINITY);
		observe("positive-zero", 0.0);
		observe("negative-zero", -0.0);
		observe("runtime-negative-zero", Std.parseFloat("-0.0"));
		observe("empty-string", "");
		observe("numeric-string", "7");
		observe("unicode-string", "héλ");
		observe("nul-string", "a\x00b");
		observe("null", null);
		observeZeroErasure(Std.parseFloat("-0.0"));
	}
}
