/**
	Exercises the first native `Reflect.compare` contract through real callbacks.

	The target supports only comparisons whose final Haxe type identifies one
	concrete domain: `Int`, `Float`, or `String`. This fixture uses both the bare
	standard function and a stored function value so generated OCaml cannot rely
	on a special case for one `Array.sort` call.
**/
class Main {
	static final compareStrings:(String, String) -> Int = Reflect.compare;
	static final compareNullableStrings:(Null<String>, Null<String>) -> Int = Reflect.compare;

	static function sign(value:Int):Int
		return value < 0 ? -1 : (value > 0 ? 1 : 0);

	/** Proves that the target's admitted Float contract fails through Haxe catch. */
	static function captureNaNFailure():String {
		try {
			Reflect.compare(Math.NaN, 0.0);
			return "missing-error";
		} catch (error:Dynamic) {
			return Std.string(error);
		}
	}

	/** Proves that a one-null String pair fails instead of entering OCaml compare. */
	static function captureNullMismatch(nullString:String):String {
		try {
			Reflect.compare(nullString, "value");
			return "missing-error";
		} catch (error:Dynamic) {
			return Std.string(error);
		}
	}

	/**
		Matches the compiler-scale inventory check that exposed the missing domain.

		The right operand is concrete String, while the guarded previous value is
		explicitly `Null<String>`. The target must keep that contextual type rather
		than widening the comparison to Dynamic.
	**/
	static function guardedOutOfOrder(previous:Null<String>, current:String):Int
		return previous != null && Reflect.compare(previous, current) >= 0 ? 1 : 0;

	static function main():Void {
		final strings = ["c", "a", "b"];
		strings.sort(Reflect.compare);

		final compareInts:(Int, Int) -> Int = Reflect.compare;
		final ints = [7, -2, 0];
		ints.sort(compareInts);

		final compareFloats:(Float, Float) -> Int = Reflect.compare;
		final floatSigns = [
			sign(compareFloats(Math.POSITIVE_INFINITY, 0.0)),
			sign(compareFloats(-0.0, 0.0)),
			sign(compareFloats(Math.NEGATIVE_INFINITY, 0.0))
		];

		Sys.println("strings=" + strings.join(","));
		Sys.println("ints=" + ints.join(","));
		Sys.println("floats=" + floatSigns.join(","));
		Sys.println("direct.int=" + sign(Reflect.compare(1, 2)));
		Sys.println("direct.float=" + sign(Reflect.compare(Math.POSITIVE_INFINITY, 0.0)));
		Sys.println("direct.string=" + sign(Reflect.compare("same", "same")));
		Sys.println("static.string=" + sign(compareStrings("a", "b")));
		final absent:Null<String> = null;
		final present:Null<String> = "value";
		Sys.println("nullable.direct.absent.absent=" + sign(Reflect.compare(absent, absent)));
		Sys.println("nullable.direct.absent.present=" + sign(Reflect.compare(absent, "value")));
		Sys.println("nullable.direct.present.absent=" + sign(Reflect.compare(present, absent)));
		Sys.println("nullable.direct.present.present=" + sign(Reflect.compare(present, "value")));
		Sys.println("nullable.callback.absent.absent=" + sign(compareNullableStrings(absent, absent)));
		Sys.println("nullable.callback.absent.present=" + sign(compareNullableStrings(absent, present)));
		Sys.println("nullable.callback.present.absent=" + sign(compareNullableStrings(present, absent)));
		Sys.println("nullable.callback.present.present=" + sign(compareNullableStrings(present, present)));
		Sys.println("nullable.guarded.absent=" + guardedOutOfOrder(absent, "value"));
		Sys.println("nullable.guarded.reverse=" + guardedOutOfOrder("z", "a"));
		final nullString:String = cast null;
		Sys.println("string.null.null=" + sign(Reflect.compare(nullString, nullString)));
		Sys.println("float.nan=" + captureNaNFailure());
		Sys.println("string.null.value=" + captureNullMismatch(nullString));
	}
}
