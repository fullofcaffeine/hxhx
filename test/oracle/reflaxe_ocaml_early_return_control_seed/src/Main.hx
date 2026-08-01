private class NestedReturnBox {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function branch(value:Int):Int {
		if (value == 0)
			return 1;
		return 2;
	}

	static function loop(limit:Int):Int {
		var index = 0;
		while (true) {
			if (index == limit)
				return index;
			index += 1;
		}
		return -1;
	}

	static function nestedBlock(value:Int):Int {
		{
			if (value > 0)
				return 4;
		}
		return 5;
	}

	static function throughTry(value:Int):Int {
		try {
			if (value > 0)
				return 7;
		} catch (_:Dynamic) {
			return 99;
		}
		return 3;
	}

	static function boolBranch(enabled:Bool):Bool {
		if (!enabled)
			return false;
		return true;
	}

	static function stringThroughTry(enabled:Bool):String {
		try {
			if (enabled)
				return "early";
		} catch (_:Dynamic) {
			return "caught";
		}
		return "late";
	}

	static function nullableStringCarrier(useNull:Bool):String {
		if (useNull)
			return null;
		return "value";
	}

	static function nestedClosure():Int {
		final local = function(flag:Bool):Int {
			if (flag)
				return 6;
			return 0;
		};
		if (local(true) == 6)
			return 8;
		return 9;
	}

	/** Exercises an exact Bool result through a planned nested return boundary. */
	static function nestedBoolClosure():Bool {
		final local = function(enabled:Bool):Bool {
			if (enabled)
				return true;
			return false;
		};
		return local(true);
	}

	/** Exercises the runtime-owned Haxe String carrier without a syntax-time cast. */
	static function nestedStringClosure():String {
		final local = function(enabled:Bool):String {
			if (enabled)
				return "nested-string";
			return "fallback";
		};
		return local(true);
	}

	/** Converts one early Int to the existing Null<Int> carrier before signaling. */
	static function nestedNullableIntClosure():Null<Int> {
		final local = function(enabled:Bool):Null<Int> {
			if (enabled)
				return 23;
			return null;
		};
		return local(true);
	}

	/** Converts one early Bool to the existing Null<Bool> carrier before signaling. */
	static function nestedNullableBoolClosure():Null<Bool> {
		final local = function(enabled:Bool):Null<Bool> {
			if (enabled)
				return true;
			return null;
		};
		return local(true);
	}

	/** Keeps a Dynamic result outside the represented nested callback matrix. */
	static function nestedDynamicClosure():Dynamic {
		final local = function(enabled:Bool):Dynamic {
			if (enabled)
				return 41;
			return "dynamic";
		};
		return local(true);
	}

	/** Keeps a zero-argument literal deferred until it has a stable occurrence identity. */
	static function nestedZeroArgumentClosure():Int {
		final enabled = true;
		final local = function():Int {
			if (enabled)
				return 43;
			return 0;
		};
		return local();
	}

	/** Keeps a closure with an unrepresented throw payload on the legacy path. */
	static function nestedUnsupportedThrowClosure():Int {
		final local = function(enabled:Bool):Int {
			if (enabled)
				return 47;
			throw [1];
		};
		return local(true);
	}

	/** Keeps nominal callback results deferred until the function-value ABI admits them. */
	static function nestedNominalClosure():NestedReturnBox {
		final local = function(enabled:Bool):NestedReturnBox {
			if (enabled)
				return new NestedReturnBox(53);
			return new NestedReturnBox(0);
		};
		return local(true);
	}

	/**
		Exercises two independently planned function literals and an outer capture.

		The inner function returns through its own private signal. The outer function
		then returns that result through a different signal, so confusing either
		function's parent identity changes the observable result or fails generation.
	**/
	static function deepNestedClosure():Int {
		final captured = 2;
		final outer = function(enabled:Bool):Int {
			final inner = function(innerEnabled:Bool):Int {
				if (innerEnabled)
					return 12 + captured;
				return 0;
			};
			if (enabled)
				return inner(true);
			return 0;
		};
		return outer(true);
	}

	/** Keeps nested `try`/`catch` behavior on the explicit legacy path in this first slice. */
	static function nestedCatchClosure():Int {
		final local = function(enabled:Bool):Int {
			try {
				if (enabled)
					return 15;
			} catch (_:Dynamic) {
				return -1;
			}
			return 0;
		};
		return local(true);
	}

	static function main() {
		printLine("branch0=" + branch(0));
		printLine("branch1=" + branch(1));
		printLine("loop3=" + loop(3));
		printLine("block1=" + nestedBlock(1));
		printLine("block0=" + nestedBlock(0));
		printLine("try1=" + throughTry(1));
		printLine("try0=" + throughTry(0));
		printLine("bool0=" + boolBranch(false));
		printLine("bool1=" + boolBranch(true));
		printLine("string1=" + stringThroughTry(true));
		printLine("string0=" + stringThroughTry(false));
		printLine("stringNull1=" + (nullableStringCarrier(true) == null));
		printLine("stringNull0=" + nullableStringCarrier(false));
		printLine("closure=" + nestedClosure());
		printLine("boolClosure=" + nestedBoolClosure());
		printLine("stringClosure=" + nestedStringClosure());
		printLine("nullableIntClosure=" + nestedNullableIntClosure());
		printLine("nullableBoolClosure=" + nestedNullableBoolClosure());
		printLine("dynamicClosure=" + (nestedDynamicClosure() == 41));
		printLine("zeroArgumentClosure=" + nestedZeroArgumentClosure());
		printLine("unsupportedThrowClosure=" + nestedUnsupportedThrowClosure());
		printLine("nominalClosure=" + nestedNominalClosure().value);
		printLine("deepClosure=" + deepNestedClosure());
		printLine("catchClosure=" + nestedCatchClosure());
		printLine("OK early_return_control");
	}
}
