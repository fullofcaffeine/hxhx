/** Executable proof that direct-call arguments run once in Haxe source order. */
class Main {
	static function sourceValue():Int {
		Sys.println("argument");
		return 41;
	}

	static function firstValue():Int {
		Sys.println("first");
		return 1;
	}

	static function secondValue():Int {
		Sys.println("second");
		return 2;
	}

	static function throwingFirst():Int {
		Sys.println("throw-first");
		throw "stop";
	}

	static function shouldNotRun():Int {
		Sys.println("second-should-not-run");
		return 2;
	}

	static function observedNullableInput():Int {
		Sys.println("nullable-int-source");
		return 9;
	}

	static function observedBoolInput():Bool {
		Sys.println("bool-source");
		return true;
	}

	static function mixedCount(label:String, value:Int):Int {
		Sys.println("mixed-count-" + label);
		return value;
	}

	static function exactMixedFlag():Bool {
		Sys.println("mixed-flag-exact");
		return true;
	}

	static function observeExistingMixedFlag(value:Null<Bool>):Null<Bool> {
		Sys.println("mixed-flag-existing");
		return value;
	}

	static function mixedDecision(label:String, value:Bool):Bool {
		Sys.println("mixed-decision-" + label);
		return value;
	}

	static function observeExistingMixedFallback(value:Null<Int>):Null<Int> {
		Sys.println("mixed-fallback-existing");
		return value;
	}

	static function exactMixedFallback():Int {
		Sys.println("mixed-fallback-exact");
		return 7;
	}

	static function main():Void {
		final result = Arithmetic.increment(sourceValue());
		Sys.println("result=" + result);
		Sys.println("two=" + Arithmetic.add(firstValue(), secondValue()));
		final recovered = try {
			Arithmetic.add(throwingFirst(), shouldNotRun());
		} catch (_:Dynamic) {
			-1;
		};
		Sys.println("caught=" + recovered);
		final existing:Null<Int> = null;
		final preserved = NullableCalls.identity(existing);
		Sys.println("nullable-preserved-null=" + (preserved == null));
		final boxed = NullableCalls.identity(observedNullableInput());
		Sys.println("nullable-boxed=" + (boxed == null ? -1 : boxed));
		final boolResult = BoolCalls.negate(observedBoolInput());
		Sys.println(boolResult ? "bool-result=true" : "bool-result=false");
		final existingNullBool:Null<Bool> = null;
		final preservedNullBool = BoolCalls.identityNullable(existingNullBool);
		Sys.println("nullable-bool-preserved-null=" + (preservedNullBool == null));
		final existingFalseBool:Null<Bool> = false;
		final preservedFalseBool = BoolCalls.identityNullable(existingFalseBool);
		Sys.println(preservedFalseBool == null ? "nullable-bool-preserved-false=missing" : (preservedFalseBool ? "nullable-bool-preserved-false=true" : "nullable-bool-preserved-false=false"));
		final boxedTrueBool = BoolCalls.identityNullable(observedBoolInput());
		Sys.println(boxedTrueBool == null ? "nullable-bool-boxed=missing" : (boxedTrueBool ? "nullable-bool-boxed=true" : "nullable-bool-boxed=false"));
		final existingMixedFlag:Null<Bool> = false;
		final preservedMixed = MixedCalls.choose(mixedCount("preserve", 41), observeExistingMixedFlag(existingMixedFlag));
		Sys.println("mixed-preserved=" + (preservedMixed == null ? -1 : preservedMixed));
		final boxedMixed = MixedCalls.choose(mixedCount("box", 42), exactMixedFlag());
		Sys.println("mixed-boxed=" + (boxedMixed == null ? -1 : boxedMixed));
		final existingMixedFallback:Null<Int> = null;
		final preservedMany = MixedCalls.chooseMany(mixedCount("many-preserve", 83), observeExistingMixedFlag(existingMixedFlag),
			mixedDecision("preserve", true), observeExistingMixedFallback(existingMixedFallback));
		Sys.println("mixed-many-preserved=" + (preservedMany == null ? -1 : preservedMany));
		final boxedMany = MixedCalls.chooseMany(mixedCount("many-box", 84), exactMixedFlag(), mixedDecision("box", true), exactMixedFallback());
		Sys.println("mixed-many-boxed=" + (boxedMany == null ? -1 : boxedMany));
		Sys.println("zero-int=" + ZeroArgCalls.exactCount());
		Sys.println(ZeroArgCalls.exactFlag() ? "zero-bool=true" : "zero-bool=false");
		Sys.println("zero-null-int=" + (ZeroArgCalls.nullableCount() == null));
		final zeroNullableFlag = ZeroArgCalls.nullableFlag();
		Sys.println(zeroNullableFlag == null ? "zero-null-bool=missing" : (zeroNullableFlag ? "zero-null-bool=true" : "zero-null-bool=false"));
		Sys.println("instance=" + new Counter().increment(5));
	}
}
