/** Public equality on erased values; no physical representation is assumed by this observation. */
class Main {
	static function plain():Void->String {
		return () -> "same";
	}

	static function capture(value:String):Void->String {
		return () -> value;
	}

	static function staticRead():String {
		return "same";
	}

	static function main():Void {
		final record = {name: "same"};
		final array = ["same"];
		final object = new Marker("same");
		final closure = () -> "same";
		final method = object.read;
		final parameterized = Sample.Item("same");
		final values:Array<{name:String, value:Dynamic}> = [
			{name: "null", value: null},
			{name: "false", value: false},
			{name: "true", value: true},
			{name: "int0", value: 0},
			{name: "int1", value: 1},
			{name: "intMinus1", value: -1},
			{name: "int255", value: 255},
			{name: "int256", value: 256},
			{name: "float0", value: 0.0},
			{name: "negativeZero", value: -0.0},
			{name: "float1", value: 1.0},
			{name: "fraction", value: 1.5},
			{name: "nan", value: Math.NaN},
			{name: "positiveInfinity", value: Math.POSITIVE_INFINITY},
			{name: "negativeInfinity", value: Math.NEGATIVE_INFINITY},
			{name: "empty", value: ""},
			{name: "text0", value: "0"},
			{name: "text1", value: "1"},
			{name: "textTrue", value: "true"},
			{name: "record", value: record},
			{name: "recordAlias", value: record},
			{name: "recordCopy", value: {name: "same"}},
			{name: "array", value: array},
			{name: "arrayAlias", value: array},
			{name: "arrayCopy", value: ["same"]},
			{name: "object", value: object},
			{name: "objectAlias", value: object},
			{name: "objectCopy", value: new Marker("same")},
			{name: "closure", value: closure},
			{name: "closureAlias", value: closure},
			{name: "closureCopy", value: () -> "same"},
			{name: "method", value: method},
			{name: "methodAgain", value: object.read},
			{name: "otherMethod", value: object.other},
			{name: "otherReceiver", value: new Marker("same").read},
			{name: "enumConstant", value: Sample.Empty},
			{name: "enumConstantAgain", value: Sample.Empty},
			{name: "enumValue", value: parameterized},
			{name: "enumAlias", value: parameterized},
			{name: "enumCopy", value: Sample.Item("same")},
			{name: "class", value: Marker},
			{name: "classAgain", value: Marker},
			{name: "otherClass", value: String},
			{name: "plainFactory", value: plain()},
			{name: "plainFactoryAgain", value: plain()},
			{name: "capturedFactory", value: capture("same")},
			{name: "capturedFactoryAgain", value: capture("same")},
			{name: "staticMethod", value: staticRead},
			{name: "staticMethodAgain", value: staticRead},
			{name: "otherEnumConstant", value: OtherSample.Empty},
			{name: "otherEnumValue", value: OtherSample.Item("same")},
			{name: "enumNan", value: Sample.Opaque(Math.NaN)},
			{name: "enumNanAgain", value: Sample.Opaque(Math.NaN)},
			{name: "enumFalse", value: Sample.Opaque(false)},
			{name: "enumZero", value: Sample.Opaque(0)},
			{name: "enumEmpty", value: Sample.Opaque("")},
			{name: "enumRecord", value: Sample.Opaque(record)},
			{name: "enumRecordAgain", value: Sample.Opaque(record)},
			{name: "enumRecordCopy", value: Sample.Opaque({name: "same"})},
			{name: "enumFunction", value: Sample.Opaque(method)},
			{name: "enumFunctionAgain", value: Sample.Opaque(object.read)},
			{name: "enumPair", value: Sample.Pair(Sample.Empty, Sample.Item("same"))},
			{name: "enumPairAgain", value: Sample.Pair(Sample.Empty, Sample.Item("same"))},
			{name: "intMin", value: -2147483648},
			{name: "floatMin", value: -2147483648.0},
			{name: "intMax", value: 2147483647},
			{name: "floatMax", value: 2147483647.0},
			{name: "unicode", value: "caf\u00e9\u0000tail"},
			{name: "unicodeAgain", value: "caf\u00e9\u0000tail"}
		];
		for (left in values) {
			var equalBits = "";
			var unequalBits = "";
			for (right in values) {
				final equal = left.value == right.value;
				final unequal = left.value != right.value;
				equalBits += equal ? "1" : "0";
				unequalBits += unequal ? "1" : "0";
			}
			Sys.println(left.name + ":" + equalBits + ":" + unequalBits);
		}
	}
}

/** Equal field values do not imply equal instance identity. */
class Marker {
	final value:String;

	public function new(value:String) {
		this.value = value;
	}

	public function read():String {
		return value;
	}

	public function other():String {
		return value;
	}
}

/** Compare enum identity separately from its constructor arguments. */
enum Sample {
	Empty;
	Item(value:String);
	Opaque(value:Dynamic);
	Pair(left:Sample, right:Sample);
}

/** A second declaration distinguishes enum identity from a shared constructor ordinal. */
enum OtherSample {
	Empty;
	Item(value:String);
}
