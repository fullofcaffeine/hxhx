class Main {
	static var field:Float = 3.0;

	static function half(value:Float):Float {
		return value / 2;
	}

	static function main() {
		// Whole numbers print without a trailing decimal point.
		var whole:Float = 2.0;
		Sys.println(Std.string(whole));
		Sys.println("float=" + whole);
		Sys.println(Std.string(-2.0));
		Sys.println(Std.string(field));
		Sys.println(Std.string(half(200)));
		Sys.println(Std.string(4294967296.0));
		Sys.println(Std.string(9007199254740992.0));
		// Signed zero keeps its sign.
		Sys.println(Std.string(0.0));
		Sys.println(Std.string(-0.0));
		// Values that need more than 12 significant digits round-trip.
		var seven:Float = 7.0;
		Sys.println(Std.string(seven / 3));
		Sys.println(Std.string(5 / 7));
		Sys.println(Std.string(0.1 + 0.2));
		Sys.println(Std.string(1234567890123.0));
		Sys.println(Std.string(1e15 + 0.5));
		Sys.println(Std.string(5.721157658961e-233));
		Sys.println(Std.string(1.7976931348623157e308));
		// Short values keep their short form.
		Sys.println(Std.string(0.1));
		Sys.println(Std.string(1.5));
		Sys.println(Std.string(12345.678));
		// Exponent form.
		Sys.println(Std.string(1e15));
		Sys.println(Std.string(1e21));
		Sys.println(Std.string(1e-5));
		Sys.println(Std.string(0.0001));
		Sys.println(Std.string(5e-324));
		// Parsed values reach the same conversion.
		Sys.println(Std.string(Std.parseFloat("6.0")));
		// Dynamic, nullable, array, and anonymous-object storage.
		var dynamicValue:Dynamic = 2.0;
		Sys.println(dynamicValue);
		Sys.println(Std.string(dynamicValue));
		var nullable:Null<Float> = 4.0;
		Sys.println(Std.string(nullable));
		Sys.println(Std.string([1.0, 2.5, seven / 3]));
		Sys.println(Std.string({a: 3.0}));
		// String building.
		var buffer = new StringBuf();
		buffer.add(8.0);
		buffer.add(" ");
		buffer.add(0.1 + 0.2);
		Sys.println(buffer.toString());
		Sys.println('interpolated=${whole}');
		// Float literals inside concatenation and a conditional.
		Sys.println("literal=" + 2.0 + " " + 0.5);
		Sys.println("ternary=" + (whole > 1 ? 4.0 : 0.25));
	}
}
