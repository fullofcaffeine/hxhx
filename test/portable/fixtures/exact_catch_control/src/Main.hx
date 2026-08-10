#if exact_catch_unrepresented_negative
private class GenericCatchError<T> extends haxe.Exception {
	public final value:T;

	public function new(value:T) {
		this.value = value;
		super("generic catch fixture");
	}
}
#end

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
	 * Proves each neighboring `try` receives its own sealed catch decision.
	 *
	 * Bool and Float use different target carriers, so both clauses must retain
	 * their own runtime tag, payload conversion, and source owner even though
	 * they appear in the same Haxe function.
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
			result += "|float:" + value;
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

	/**
	 * Runs a callback whose result is deliberately ignored by Haxe.
	 *
	 * `Array.push` returns the new array length, but this function promises
	 * `Void`. Generated OCaml must therefore discard both the callback's normal
	 * result and the final catch call's integer result so every branch is `unit`.
	 */
	static function capture(action:() -> Void, problems:Array<String>):Void {
		try {
			action();
		} catch (_:Int) {
			problems.push("wrong-int");
		} catch (message:String) {
			problems.push(message);
		}
	}

	static function callbackVoidResult():String {
		final problems = new Array<String>();
		capture(() -> throwString("callback"), problems);
		return "callback=" + problems.join("|");
	}

	/**
	 * Repeats the production output-transaction catch order.
	 *
	 * The sealed chain records the native enum carrier for `haxe.io.Error`, the
	 * Haxe exception-wrapper rule, and the final String carrier before generated
	 * OCaml is built. Its `Void` branch-result rule must reach syntax unchanged.
	 */
	static function captureProductionTypes(action:() -> Void, problems:Array<String>):Void {
		try {
			action();
		} catch (_:haxe.io.Error) {
			problems.push("io-error");
		} catch (_:haxe.Exception) {
			problems.push("wrong-exception");
		} catch (message:String) {
			problems.push(message);
		}
	}

	static function typedVoidResult():String {
		final problems = new Array<String>();
		captureProductionTypes(() -> throw haxe.io.Error.Custom("typed"), problems);
		return "typedVoid=" + problems.join("|");
	}

	/**
	 * Leaves a Boolean-returning call at the end of a direct `Void` catch.
	 *
	 * This complements `capture`: the result-discard rule belongs to the typed
	 * `Void` context, not to one particular callback or return type.
	 */
	static function discardBoolFromCatch(values:Array<Int>):Void {
		try {
			throwInt();
		} catch (_:Int) {
			values.remove(7);
		} catch (_:Dynamic) {
			values.remove(8);
		}
	}

	static function directVoidResult():String {
		final values = [7];
		discardBoolFromCatch(values);
		return "directBool=" + values.length;
	}

	/** A non-`Void` `try` must keep the selected branch value. */
	static function valueProducingCatch():String {
		final value = try {
			throwString("value");
			"wrong";
		} catch (_:String) {
			"kept";
		}
		return "valueResult=" + value;
	}

	#if exact_catch_unrepresented_negative
	/**
		Exercises the hard-cut failure for a catch type with no sealed carrier.

		The generic exception is valid Haxe but intentionally outside the admitted
		monomorphic-class catch set. The test invokes this function only in a separate
		negative compile and requires the planner to stop before target syntax can
		invent matching or payload recovery.
	**/
	static function unsupportedCatch():Void {
		try {
			throw new GenericCatchError<String>("blocked");
		} catch (_:GenericCatchError<Dynamic>) {}
	}
	#end

	static function main():Void {
		#if exact_catch_unrepresented_negative
		unsupportedCatch();
		#end
		Sys.println([
			orderedBool(),
			exactFirst(),
			exactString(),
			nullString(),
			outerPropagation(),
			rethrow(),
			independentAdmission(),
			targetNativeFailure(),
			callbackVoidResult(),
			typedVoidResult(),
			directVoidResult(),
			valueProducingCatch()
		].join(","));
	}
}
