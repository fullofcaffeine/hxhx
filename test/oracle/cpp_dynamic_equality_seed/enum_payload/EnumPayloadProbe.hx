/**
	Observe conversion inside enum equality independently from ordinary Dynamic
	equality. Dynamic is intentional at this public comparison boundary.
 */
class EnumPayloadProbe {
	public static var calls:Int = 0;

	static function compare(label:String, left:Dynamic, right:Dynamic):Void {
		final a:Dynamic = Envelope.Payload(left);
		final b:Dynamic = Envelope.Payload(right);
		calls = 0;
		try {
			final equal = a == b;
			final unequal = a != b;
			Sys.println(label + ":" + equal + ":" + unequal + ":" + calls);
		} catch (failure:String) {
			Sys.println(label + ":throw:" + failure + ":" + calls);
		}
	}

	static function main():Void {
		final values:Array<{name:String, value:Dynamic}> = [
			{name: "false", value: false},
			{name: "true", value: true},
			{name: "zero", value: 0},
			{name: "one", value: 1},
			{name: "minusOne", value: -1},
			{name: "fraction", value: 1.5},
			{name: "negativeFraction", value: -1.5},
			{name: "nan", value: Math.NaN},
			{name: "infinity", value: Math.POSITIVE_INFINITY},
			{name: "negativeInfinity", value: Math.NEGATIVE_INFINITY},
			{name: "empty", value: ""},
			{name: "textZero", value: "0"},
			{name: "textOne", value: "1"},
			{name: "textFraction", value: "1.5"},
			{name: "textOtherFraction", value: "1.9"},
			{name: "textSuffix", value: "1x"},
			{name: "textPrefix", value: "x1"},
			{name: "textSpace", value: " 1"},
			{name: "textExponent", value: "1e0"},
			{name: "textHex", value: "0x1"},
			{name: "textNan", value: "NaN"},
			{name: "textInfinity", value: "Infinity"},
			{name: "textInf", value: "inf"},
			{name: "textNegativeInf", value: "-inf"},
			{name: "textTrue", value: "true"},
			{name: "textNull", value: "null"},
			{name: "textNulSuffix", value: "1\u0000x"}
		];
		for (left in values) {
			var equalBits = "";
			var unequalBits = "";
			for (right in values) {
				final a:Dynamic = Envelope.Payload(left.value);
				final b:Dynamic = Envelope.Payload(right.value);
				equalBits += a == b ? "1" : "0";
				unequalBits += a != b ? "1" : "0";
			}
			Sys.println(left.name + ":" + equalBits + ":" + unequalBits);
		}
		compare("string-object", "same", new TextValue());
		compare("object-string", new TextValue(), "same");
		compare("number-object", 0, new TextValue());
		compare("string-throwing", "same", new FailingText());
		compare("string-null-return", "null", new NullText());
		compare("string-array", "[1,2]", [1, 2]);
		compare("string-enum", "Empty", Envelope.Empty);
		compare("string-payload", "Payload(same)", Envelope.Payload(new TextValue()));
		compare("string-payload-null", "Payload(null)", Envelope.Payload(null));
		compare("string-pair", "Pair(1,same)", Envelope.Pair(1, new TextValue()));
		compare("null-null", null, null);
		compare("null-string", null, "null");
	}
}

/** Separate constructors expose enum identity and payload traversal. */
enum Envelope {
	Empty;
	Payload(value:Dynamic);
	Pair(left:Dynamic, right:Dynamic);
}

/** A conversion with an observable effect distinguishes conversion from identity. */
class TextValue {
	public function new() {}

	public function toString():String {
		EnumPayloadProbe.calls++;
		return "same";
	}
}

/** A conversion failure must escape the comparison. */
class FailingText {
	public function new() {}

	public function toString():String {
		EnumPayloadProbe.calls++;
		throw "conversion";
	}
}

/** Null returned from a String method is distinct from the literal text null. */
class NullText {
	public function new() {}

	public function toString():String {
		EnumPayloadProbe.calls++;
		return null;
	}
}
