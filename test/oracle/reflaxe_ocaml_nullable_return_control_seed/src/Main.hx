class Main {
	static var caught:Bool = false;

	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function describeInt(value:Null<Int>):String {
		return value == null ? "null" : Std.string(value);
	}

	static function describeBool(value:Null<Bool>):String {
		return value == null ? "null" : (value == true ? "true" : "false");
	}

	static function chooseInt(stop:Bool, value:Null<Int>):Null<Int> {
		if (stop)
			return value;
		return 7;
	}

	static function chooseBool(stop:Bool, value:Null<Bool>):Null<Bool> {
		if (stop)
			return value;
		return true;
	}

	static function preserveIntFallback(stop:Bool, early:Null<Int>, fallback:Null<Int>):Null<Int> {
		if (stop)
			return early;
		return fallback;
	}

	static function preserveBoolFallback(stop:Bool, early:Null<Bool>, fallback:Null<Bool>):Null<Bool> {
		if (stop)
			return early;
		return fallback;
	}

	static function convertInt(stop:Bool, early:Int, fallback:Null<Int>):Null<Int> {
		if (stop)
			return early;
		return fallback;
	}

	static function convertBool(stop:Bool, early:Bool, fallback:Null<Bool>):Null<Bool> {
		if (stop)
			return early;
		return fallback;
	}

	static function mixedInt(mode:Int, early:Int, nullable:Null<Int>):Null<Int> {
		if (mode == 0)
			return early;
		if (mode == 1)
			return nullable;
		return 9;
	}

	static function intThroughLoop(run:Bool, early:Int, fallback:Null<Int>):Null<Int> {
		while (run)
			return early;
		return fallback;
	}

	static function intThroughTry(stop:Bool, value:Null<Int>):Null<Int> {
		caught = false;
		try {
			if (stop)
				return value;
		} catch (_:Dynamic) {
			caught = true;
		}
		return 8;
	}

	static function boolThroughTry(stop:Bool, value:Null<Bool>):Null<Bool> {
		caught = false;
		try {
			if (stop)
				return value;
		} catch (_:Dynamic) {
			caught = true;
		}
		return false;
	}

	static function primitiveBoolThroughTry(stop:Bool, early:Bool, fallback:Null<Bool>):Null<Bool> {
		caught = false;
		try {
			if (stop)
				return early;
		} catch (_:Dynamic) {
			caught = true;
		}
		return fallback;
	}

	static function printInt(label:String, value:Null<Int>):Void {
		printLine(label + "=" + describeInt(value));
	}

	static function printBool(label:String, value:Null<Bool>):Void {
		printLine(label + "=" + describeBool(value));
	}

	static function main() {
		printInt("intNull", chooseInt(true, null));
		printInt("intZero", chooseInt(true, 0));
		printInt("intPositive", chooseInt(true, 4));
		printInt("intDirect", chooseInt(false, null));
		printBool("boolNull", chooseBool(true, null));
		printBool("boolFalse", chooseBool(true, false));
		printBool("boolTrue", chooseBool(true, true));
		printBool("boolDirect", chooseBool(false, null));
		printInt("intCarrierFallback", preserveIntFallback(false, null, 5));
		printBool("boolCarrierFallback", preserveBoolFallback(false, true, false));
		printInt("intConvertedZero", convertInt(true, 0, null));
		printInt("intConvertedPositive", convertInt(true, 6, null));
		printInt("intConvertedFallback", convertInt(false, 6, null));
		printBool("boolConvertedFalse", convertBool(true, false, null));
		printBool("boolConvertedTrue", convertBool(true, true, null));
		printBool("boolConvertedFallback", convertBool(false, true, null));
		printInt("mixedConverted", mixedInt(0, 3, null));
		printInt("mixedNullable", mixedInt(1, 3, null));
		printInt("mixedDirect", mixedInt(2, 3, null));
		printInt("loopConverted", intThroughLoop(true, 0, null));
		printInt("loopFallback", intThroughLoop(false, 4, null));

		printInt("tryIntNull", intThroughTry(true, null));
		printLine("tryIntNullCaught=" + caught);
		printInt("tryIntZero", intThroughTry(true, 0));
		printLine("tryIntZeroCaught=" + caught);
		printBool("tryBoolFalse", boolThroughTry(true, false));
		printLine("tryBoolFalseCaught=" + caught);
		printInt("tryDirect", intThroughTry(false, null));
		printLine("tryDirectCaught=" + caught);
		printBool("tryPrimitiveFalse", primitiveBoolThroughTry(true, false, null));
		printLine("tryPrimitiveFalseCaught=" + caught);
		printBool("tryPrimitiveFallback", primitiveBoolThroughTry(false, true, null));
		printLine("tryPrimitiveFallbackCaught=" + caught);
		printLine("OK nullable_return_control");
	}
}
