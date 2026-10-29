/**
	Black-box native reference for numeric erasure and catch matching.
	Dynamic is confined to the observation boundary; every payload is checked
	through public type predicates and independently specified handler results.
**/
class Main {
	static var observations:Int = 0;

	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function intCatch(value:Dynamic):Bool {
		try {
			try {
				throw value;
			} catch (_:Int) {
				return true;
			}
		} catch (_:Dynamic) {
			return false;
		}
		return false;
	}

	static function ordered(value:Dynamic):Int {
		try {
			throw value;
		} catch (_:Bool) {
			return 4;
		} catch (_:Int) {
			return 1;
		} catch (_:Float) {
			return 2;
		} catch (_:String) {
			return 3;
		} catch (_:Dynamic) {
			return 0;
		}
	}

	static function floatBinding(value:Dynamic, expected:Float):Void {
		try {
			throw value;
		} catch (number:Float) {
			if (Math.isNaN(expected))
				require(Math.isNaN(number), "NaN binding changed");
			else {
				require(number == expected, "Float binding changed value");
				if (number == 0)
					require(1.0 / number > 0, "erased zero retained a negative sign");
			}
		}
	}

	static function opaque(value:Dynamic, expected:Float, integer:Bool):Void {
		final kindIsInt = switch Type.typeof(value) {
			case TInt: true;
			case TFloat: false;
			case _: throw "erasure produced a non-numeric kind";
		};
		require(kindIsInt == integer, "erasure selected the wrong numeric kind: " + expected);
		final memberIsInt = expected >= -2147483648.0 && expected <= 2147483647.0 && Math.floor(expected) == expected;
		require(Std.isOfType(value, Int) == memberIsInt, "numeric membership disagrees with its independent range contract: " + expected);
		require(Std.isOfType(value, Float), "numeric erasure lost Float compatibility");
		require(intCatch(value) == integer, "Int handler disagrees with membership");
		require(ordered(value) == (integer ? 1 : 2), "raw numeric handler order changed");
		floatBinding(value, expected);
		final wrapper = new haxe.ValueException(value);
		require(intCatch(wrapper) == memberIsInt, "wrapped Int handler disagrees with membership");
		// The pinned upstream wrapper path chooses Float over the earlier Int
		// handler. Keep this observation separate from raw authored handler order.
		require(ordered(wrapper) == 2, "wrapped primitive handler group changed");
		floatBinding(wrapper, expected);
		observations++;
	}

	/** A typed parameter prevents literal-folding decisions from serving as runtime erasure evidence. */
	static function observe(value:Float, integer:Bool):Void {
		opaque(NumericTransport.erase(value), value, integer);
		opaque(NumericTransport.eraseAny(value), value, integer);
		opaque(NumericTransport.thrown(value), value, integer);
		opaque(NumericTransport.called(value), value, integer);
		opaque(NumericTransport.closure(value), value, integer);
		opaque(NumericTransport.initialized(value), value, integer);
		opaque(NumericTransport.assigned(value), value, integer);
		opaque(NumericTransport.record(value), value, integer);
		opaque(NumericTransport.recordWrite(value), value, integer);
		opaque(NumericTransport.array(value), value, integer);
		opaque(NumericTransport.arrayPush(value), value, integer);
		opaque(NumericTransport.arrayWrite(value), value, integer);
		opaque(NumericTransport.mapLiteral(value), value, integer);
		opaque(NumericTransport.mapSet(value), value, integer);
	}

	static function main():Void {
		for (step in -8192...8193) {
			final value:Float = step / 2.0;
			// This expectation is a hypothesis from prior samples, now checked at
			// every integer and half-integer in the surrounding interval.
			observe(value, step >= -2 && step <= 510 && step % 2 == 0);
		}
		for (value in [
			-2147483649.0,
			-2147483648.0,
			-2147483647.0,
			2147483646.0,
			2147483647.0,
			2147483648.0,
			-0.25,
			0.25,
			254.99999999999997,
			255.00000000000003,
			Math.NaN,
			Math.POSITIVE_INFINITY,
			Math.NEGATIVE_INFINITY
		])
			observe(value, false);
		final negativeZero = Std.parseFloat("-0.0");
		require(1.0 / NumericTransport.preserve(negativeZero) < 0, "typed Float transport changed signed zero");
		observe(negativeZero, true);
		for (value in [-2147483647 - 1, -4096, -2, -1, 0, 1, 255, 256, 4096, 2147483647])
			opaque(value, value, true);
		require(ordered(true) == 4 && ordered("7") == 3 && ordered(null) == 0, "non-numeric values changed handler kind");
		require(ordered(new haxe.ValueException(true)) == 4, "wrapped Bool lost authored order");
		require(ordered(new haxe.ValueException("7")) == 3, "wrapped String lost authored order");
		Sys.println("CPP_NUMERIC_ERASURE_REFERENCE:PASS observations=" + observations);
	}
}
