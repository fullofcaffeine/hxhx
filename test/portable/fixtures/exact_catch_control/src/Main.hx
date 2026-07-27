class Main {
	static function throwInt():Void {
		throw 41;
	}

	static function throwBool():Void {
		throw true;
	}

	static function throwString(value:String):Void {
		throw value;
	}

	static function orderedBool():String {
		try {
			throwBool();
		} catch (_:Int) {
			return "ordered=wrong-int";
		} catch (value:Bool) {
			return "ordered=" + value;
		} catch (_:Dynamic) {
			return "ordered=wrong-dynamic";
		}
		return "ordered=miss";
	}

	static function exactFirst():String {
		try {
			throwInt();
		} catch (value:Int) {
			return "exactFirst=" + value;
		} catch (_:Dynamic) {
			return "exactFirst=wrong-dynamic";
		}
		return "exactFirst=miss";
	}

	static function exactString():String {
		try {
			throwString("boom");
		} catch (value:String) {
			return "string=" + value;
		} catch (_:Dynamic) {
			return "string=wrong-dynamic";
		}
		return "string=miss";
	}

	static function nullString():String {
		final value:String = null;
		try {
			throwString(value);
		} catch (_:String) {
			return "nullString=wrong-string";
		} catch (_:Dynamic) {
			return "nullString=dynamic";
		}
		return "nullString=miss";
	}

	static function propagate():String {
		try {
			throwInt();
		} catch (_:String) {
			return "propagate=wrong-string";
		} catch (_:Bool) {
			return "propagate=wrong-bool";
		}
		return "propagate=miss";
	}

	static function outerPropagation():String {
		try {
			return propagate();
		} catch (value:Int) {
			return "propagate=" + value;
		}
	}

	static function rethrow():String {
		try {
			try {
				throwInt();
			} catch (value:Int) {
				throw value + 1;
			}
		} catch (value:Int) {
			return "rethrow=" + value;
		}
		return "rethrow=miss";
	}

	/**
	 * Proves admission is decided for each `try`, rather than disabling every
	 * exact catch in a function that also contains an unsupported Float catch.
	 */
	static function independentAdmission():String {
		var result = "";
		try {
			throwBool();
		} catch (value:Bool) {
			result = "exact:" + value;
		}
		try {
			throw 1.5;
		} catch (value:Float) {
			result += "|legacy:" + value;
		}
		return "independent=" + result;
	}

	/**
	 * Integer remainder by zero raises an OCaml exception before any
	 * compiler-owned Haxe throw signal exists. The Dynamic clause must still
	 * receive that target-native exception after the preceding Int clause
	 * declines it.
	 */
	static function targetNativeFailure():String {
		var zero = 0;
		try {
			final value = 1 % zero;
			return "native=wrong:" + value;
		} catch (_:Int) {
			return "native=wrong-int";
		} catch (_:Dynamic) {
			return "native=dynamic";
		}
	}

	static function main():Void {
		Sys.println([
			orderedBool(),
			exactFirst(),
			exactString(),
			nullString(),
			outerPropagation(),
			rethrow(),
			independentAdmission(),
			targetNativeFailure()
		].join(","));
	}
}
