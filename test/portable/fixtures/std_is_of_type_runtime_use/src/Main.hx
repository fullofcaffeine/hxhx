enum SampleKind {
	Ready;
}

/** A nominal value used to exercise the general runtime type check. */
class SampleMarker {
	public function new() {}
}

/**
	Exercises each target strategy used by `Std.isOfType`.

	The first two checks also prove that the source value is evaluated once when
	the answer is already known from its static Haxe type.
**/
class Main {
	static var effectCount = 0;
	static final initialValue:Dynamic = "ready";
	static final initialStringCheck = Std.isOfType(initialValue, String);

	static function sideEffectInt():Int {
		effectCount += 1;
		return 7;
	}

	static function sideEffectString():String {
		effectCount += 1;
		return "seven";
	}

	static function main():Void {
		final staticTrue = Std.isOfType(sideEffectInt(), Int);
		Sys.println('static-true=$staticTrue effects=$effectCount');
		final staticFalse = Std.isOfType(sideEffectString(), Int);
		Sys.println('static-false=$staticFalse effects=$effectCount');

		final dynamicInt:Dynamic = 7;
		final dynamicBool:Dynamic = true;
		final dynamicString:Dynamic = "ready";
		final dynamicArray:Dynamic = [1, 2, 3];
		final dynamicMarker:Dynamic = new SampleMarker();
		final dynamicKind:Dynamic = SampleKind.Ready;
		final nested = () -> Std.isOfType(dynamicInt, Int);

		Sys.println('dynamic-int=${Std.isOfType(dynamicInt, Int)}');
		Sys.println('dynamic-float=${Std.isOfType(dynamicInt, Float)}');
		Sys.println('dynamic-bool=${Std.isOfType(dynamicBool, Bool)}');
		Sys.println('dynamic-int-bool=${Std.isOfType(dynamicInt, Bool)}');
		Sys.println('dynamic-string=${Std.isOfType(dynamicString, String)}');
		Sys.println('dynamic-array=${Std.isOfType(dynamicArray, Array)}');
		Sys.println('dynamic-string-array=${Std.isOfType(dynamicString, Array)}');
		Sys.println('dynamic-class=${Std.isOfType(dynamicMarker, SampleMarker)}');
		Sys.println('dynamic-enum=${Std.isOfType(dynamicKind, SampleKind)}');
		Sys.println('operator-int=${dynamicInt is Int}');
		Sys.println('operator-array=${dynamicArray is Array}');
		Sys.println('nested-int=${nested()}');
		Sys.println('standalone-string=$initialStringCheck');
	}
}
