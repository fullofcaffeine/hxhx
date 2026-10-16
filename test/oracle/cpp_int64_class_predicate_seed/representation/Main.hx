/** Observe public Int64 membership together with the value category after Dynamic transport. */
class Main {
	/** Dynamic is the public predicate input; inspect it immediately without interpreting its native storage. */
	static function show(label:String, value:Dynamic):Void {
		var kind = switch Type.typeof(value) {
			case TInt: "int";
			case TFloat: "float";
			case TBool: "bool";
			case TNull: "null";
			case _: "other";
		};
		Sys.println(label + ":" + haxe.Int64.isInt64(value) + ":" + kind);
	}

	static function main():Void {
		show("wide", haxe.Int64.make(1, 2));
		show("zero64", haxe.Int64.ofInt(0));
		show("null", null);
		show("int", 2);
		show("negative", -2);
		show("min", -2147483647 - 1);
		show("max", 2147483647);
		show("float2", 2.0);
		show("fraction", 2.5);
		show("float_runtime", Std.parseFloat("2.0"));
		show("float_zero", 0.0);
		show("float_one", 1.0);
		show("float_minus_one", -1.0);
		show("float_127", 127.0);
		show("float_128", 128.0);
		show("float_255", 255.0);
		show("float_256", 256.0);
		show("float_257", 257.0);
		show("negative_float", -2.0);
		show("minus_zero", -0.0);
		show("float_min", -2147483648.0);
		show("float_max", 2147483647.0);
		show("above_int", 2147483648.0);
		show("below_int", -2147483649.0);
		show("wide_float", 4294967296.0);
		show("wide_negative_float", -4294967296.0);
		show("nan", Math.NaN);
		show("positive_infinity", Math.POSITIVE_INFINITY);
		show("negative_infinity", Math.NEGATIVE_INFINITY);
		show("true", true);
		show("false", false);
		show("string", "2");
		show("array", [1, 2]);
		show("record", {high: 1, low: 2});
	}
}
