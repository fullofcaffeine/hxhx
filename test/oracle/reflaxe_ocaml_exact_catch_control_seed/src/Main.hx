class Main {
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

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
			return "propagate=wrong-inner";
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

	static function independentChains():String {
		var out = "";
		try {
			throwBool();
		} catch (value:Bool) {
			out += "bool:" + value;
		}
		try {
			throwString("ok");
		} catch (value:String) {
			out += "|string:" + value;
		}
		return "independent=" + out;
	}

	/**
	 * Runs a callback whose result is deliberately ignored by Haxe.
	 *
	 * `Array.push` returns the new array length, but this function promises
	 * `Void`. Every target must therefore discard the final catch call's value.
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
	 * Uses the same typed catch order as the hxhx output transaction.
	 *
	 * The enum catch ends in `Array.push`, whose integer result is ignored
	 * because the callback and this function both return `Void`.
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

	static function legacyVoidResult():String {
		final problems = new Array<String>();
		captureProductionTypes(() -> throw haxe.io.Error.Custom("legacy"), problems);
		return "legacyVoid=" + problems.join("|");
	}

	/** A Boolean-returning call at the end of a `Void` catch is discarded. */
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

	/** A non-`Void` `try` keeps the selected branch value. */
	static function valueProducingCatch():String {
		final value = try {
			throwString("value");
			"wrong";
		} catch (_:String) {
			"kept";
		}
		return "valueResult=" + value;
	}

	static function main():Void {
		printLine([
			orderedBool(),
			exactFirst(),
			exactString(),
			nullString(),
			outerPropagation(),
			rethrow(),
			independentChains(),
			callbackVoidResult(),
			legacyVoidResult(),
			directVoidResult(),
			valueProducingCatch()
		].join(","));
	}
}
