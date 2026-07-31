import haxe.io.Bytes;

/**
	Black-box Haxe 4.3.7 oracle for Float32 and Float64 Bytes operations.

	The fixture asserts stable observable behavior shared by Eval and Neko. It
	deliberately checks NaN classification instead of one payload because the two
	oracle targets encode `Math.NaN` with different double-precision payload bits.
**/
class Main {
	static final order:Array<String> = [];

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function orderedBytes(label:String, value:Bytes):Bytes {
		order.push(label);
		return value;
	}

	static function orderedInt(label:String, value:Int):Int {
		order.push(label);
		return value;
	}

	static function orderedNullableInt(label:String, value:Null<Int>):Null<Int> {
		order.push(label);
		return value;
	}

	static function orderedFloat(label:String, value:Float):Float {
		order.push(label);
		return value;
	}

	static function expectFailure(operation:Void->Void):Void {
		var failed = false;
		try {
			operation();
		} catch (_:Dynamic) {
			failed = true;
		}
		require(failed, "expected Bytes operation to fail");
	}

	static function expectFailureWithoutMutation(value:Bytes, operation:Void->Void):Void {
		final before = value.toHex();
		expectFailure(operation);
		require(value.toHex() == before, "failed Bytes operation mutated its receiver");
	}

	static function isNegativeZero(value:Float):Bool {
		return value == 0.0 && 1.0 / value == Math.NEGATIVE_INFINITY;
	}

	static function isPositiveZero(value:Float):Bool {
		return value == 0.0 && 1.0 / value == Math.POSITIVE_INFINITY;
	}

	static function checkFloat32():Void {
		final value = Bytes.alloc(4);
		value.setFloat(0, 1.0);
		require(value.toHex() == "0000803f" && value.getFloat(0) == 1.0, "Float32 one lost its little-endian representation");

		value.setFloat(0, -2.5);
		require(value.toHex() == "000020c0" && value.getFloat(0) == -2.5, "Float32 finite value changed");

		value.setFloat(0, 0.1);
		final rounded = value.getFloat(0);
		require(value.toHex() == "cdcccc3d" && rounded > 0.1 && rounded < 0.10000001, "Float32 rounding changed");

		value.setFloat(0, 0.0);
		require(value.toHex() == "00000000" && isPositiveZero(value.getFloat(0)), "Float32 positive zero changed");
		value.setFloat(0, -0.0);
		require(value.toHex() == "00000080" && isNegativeZero(value.getFloat(0)), "Float32 negative zero changed");

		value.setFloat(0, Math.POSITIVE_INFINITY);
		require(value.toHex() == "0000807f" && value.getFloat(0) == Math.POSITIVE_INFINITY, "Float32 positive Infinity changed");
		value.setFloat(0, Math.NEGATIVE_INFINITY);
		require(value.toHex() == "000080ff" && value.getFloat(0) == Math.NEGATIVE_INFINITY, "Float32 negative Infinity changed");

		value.setFloat(0, Math.NaN);
		require(Math.isNaN(value.getFloat(0)) && value.toHex() != "0000807f" && value.toHex() != "000080ff", "Float32 NaN lost its classification");
		require(Math.isNaN(Bytes.ofHex("0100c07f").getFloat(0)), "Float32 NaN decode changed");

		final smallestSubnormal = Bytes.ofHex("01000000").getFloat(0);
		value.setFloat(0, smallestSubnormal);
		require(value.toHex() == "01000000", "Float32 subnormal round trip changed");

		order.resize(0);
		orderedBytes("float-set-receiver", value).setFloat(orderedInt("float-set-position", 0), orderedFloat("float-set-value", 1.25));
		require(order.join(",") == "float-set-receiver,float-set-position,float-set-value", "Float32 write evaluation order changed");
		order.resize(0);
		final read = orderedBytes("float-get-receiver", value).getFloat(orderedInt("float-get-position", 0));
		require(read == 1.25 && order.join(",") == "float-get-receiver,float-get-position", "Float32 read evaluation order changed");

		order.resize(0);
		expectFailureWithoutMutation(value,
			() -> orderedBytes("float-null-position-receiver",
				value).setFloat(orderedNullableInt("float-null-position", null), orderedFloat("float-null-position-value", 2.5)));
		require(order.join(",") == "float-null-position-receiver,float-null-position,float-null-position-value",
			"Float32 null position skipped or reordered a call input");
	}

	static function checkFloat64():Void {
		final value = Bytes.alloc(8);
		value.setDouble(0, 1.0);
		require(value.toHex() == "000000000000f03f" && value.getDouble(0) == 1.0, "Float64 one lost its little-endian representation");

		value.setDouble(0, -2.5);
		require(value.toHex() == "00000000000004c0" && value.getDouble(0) == -2.5, "Float64 finite value changed");

		value.setDouble(0, 0.1);
		require(value.toHex() == "9a9999999999b93f" && value.getDouble(0) == 0.1, "Float64 finite precision changed");

		value.setDouble(0, 0.0);
		require(value.toHex() == "0000000000000000" && isPositiveZero(value.getDouble(0)), "Float64 positive zero changed");
		value.setDouble(0, -0.0);
		require(value.toHex() == "0000000000000080" && isNegativeZero(value.getDouble(0)), "Float64 negative zero changed");

		value.setDouble(0, Math.POSITIVE_INFINITY);
		require(value.toHex() == "000000000000f07f" && value.getDouble(0) == Math.POSITIVE_INFINITY, "Float64 positive Infinity changed");
		value.setDouble(0, Math.NEGATIVE_INFINITY);
		require(value.toHex() == "000000000000f0ff" && value.getDouble(0) == Math.NEGATIVE_INFINITY, "Float64 negative Infinity changed");

		value.setDouble(0, Math.NaN);
		require(Math.isNaN(value.getDouble(0)) && value.toHex() != "000000000000f07f" && value.toHex() != "000000000000f0ff",
			"Float64 NaN lost its classification");
		require(Math.isNaN(Bytes.ofHex("010000000000f87f").getDouble(0)), "Float64 NaN decode changed");

		final smallestSubnormal = Bytes.ofHex("0100000000000000").getDouble(0);
		value.setDouble(0, smallestSubnormal);
		require(value.toHex() == "0100000000000000", "Float64 subnormal round trip changed");

		order.resize(0);
		orderedBytes("double-set-receiver", value).setDouble(orderedInt("double-set-position", 0), orderedFloat("double-set-value", 1.25));
		require(order.join(",") == "double-set-receiver,double-set-position,double-set-value", "Float64 write evaluation order changed");

		order.resize(0);
		expectFailureWithoutMutation(value,
			() -> orderedBytes("double-null-position-receiver",
				value).setDouble(orderedNullableInt("double-null-position", null), orderedFloat("double-null-position-value", 2.5)));
		require(order.join(",") == "double-null-position-receiver,double-null-position,double-null-position-value",
			"Float64 null position skipped or reordered a call input");
	}

	static function main():Void {
		checkFloat32();
		checkFloat64();
		Sys.println("HAXE_4_3_7_BYTES_FLOAT_ORACLE:PASS");
	}
}
