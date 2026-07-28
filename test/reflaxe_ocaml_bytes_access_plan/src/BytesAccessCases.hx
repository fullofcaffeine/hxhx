package;

import haxe.io.Bytes;
import haxe.io.BytesData;

/**
	Typed target inputs and Haxe 4.3.7 behavior cases for Bytes access.

	The macro fixture observes the target-selected declarations. Running this
	class directly exercises upstream Haxe's public behavior: evaluation order,
	unsigned byte and UInt16 values, signed Int32 and Int64 values, little-endian
	ordering, write masking or bit preservation, shared data, and single-byte
	nullable-argument conversion. The target runtime fixture separately proves
	reflaxe.ocaml's deterministic checked-bounds policy.
**/
class BytesAccessCases {
	static function bytes(values:Array<Int>):Bytes {
		final result = Bytes.alloc(values.length);
		for (index in 0...values.length)
			result.set(index, values[index]);
		return result;
	}

	static function expectFailure(expected:String, operation:Void->Void):Void {
		var actual:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			actual = Std.string(error);
		}
		if (actual != expected)
			throw 'expected "$expected", received "${actual == null ? "no failure" : actual}"';
	}

	public static function get(bytes:Bytes, position:Int):Int {
		return bytes.get(position);
	}

	public static function getNullablePosition(bytes:Bytes, position:Null<Int>):Int {
		return bytes.get(position);
	}

	public static function set(bytes:Bytes, position:Int, value:Int):Void {
		bytes.set(position, value);
	}

	public static function setNullableValue(bytes:Bytes, position:Int, value:Null<Int>):Void {
		bytes.set(position, value);
	}

	public static function getUInt16(bytes:Bytes, position:Int):Int {
		return bytes.getUInt16(position);
	}

	public static function setUInt16(bytes:Bytes, position:Int, value:Int):Void {
		bytes.setUInt16(position, value);
	}

	public static function getInt32(bytes:Bytes, position:Int):Int {
		return bytes.getInt32(position);
	}

	public static function setInt32(bytes:Bytes, position:Int, value:Int):Void {
		bytes.setInt32(position, value);
	}

	public static function getInt64(bytes:Bytes, position:Int):haxe.Int64 {
		return bytes.getInt64(position);
	}

	public static function setInt64(bytes:Bytes, position:Int, value:haxe.Int64):Void {
		bytes.setInt64(position, value);
	}

	public static function getData(bytes:Bytes):BytesData {
		return bytes.getData();
	}

	public static function fastGet(data:BytesData, position:Int):Int {
		return Bytes.fastGet(data, position);
	}

	public static function getInSourceOrder(receiver:Void->Bytes, position:Void->Int):Int {
		return receiver().get(position());
	}

	public static function setInSourceOrder(receiver:Void->Bytes, position:Void->Int, value:Void->Int):Void {
		receiver().set(position(), value());
	}

	public static function getUInt16InSourceOrder(receiver:Void->Bytes, position:Void->Int):Int {
		return receiver().getUInt16(position());
	}

	public static function setInt32InSourceOrder(receiver:Void->Bytes, position:Void->Int, value:Void->Int):Void {
		receiver().setInt32(position(), value());
	}

	public static function getInt64InSourceOrder(receiver:Void->Bytes, position:Void->Int):haxe.Int64 {
		return receiver().getInt64(position());
	}

	public static function setInt64InSourceOrder(receiver:Void->Bytes, position:Void->Int, value:Void->haxe.Int64):Void {
		receiver().setInt64(position(), value());
	}

	public static function getDataInSourceOrder(receiver:Void->Bytes):BytesData {
		return receiver().getData();
	}

	public static function fastGetInSourceOrder(data:Void->BytesData, position:Void->Int):Int {
		return Bytes.fastGet(data(), position());
	}

	public static function userLookalike(value:BytesAccessLookalike):Int {
		value.set(0, 1);
		return value.get(0) + value.fastGet(value.getData(), 0);
	}

	public static function main():Void {
		final order:Array<String> = [];
		final value = bytes([1, 2, 3]);
		final read = getInSourceOrder(() -> {
			order.push("get-receiver");
			return value;
		}, () -> {
			order.push("get-position");
			return 1;
		});
		if (read != 2 || order.join(",") != "get-receiver,get-position")
			throw "Haxe Bytes get evaluation or value behavior changed";

		order.resize(0);
		setInSourceOrder(() -> {
			order.push("set-receiver");
			return value;
		}, () -> {
			order.push("set-position");
			return 1;
		}, () -> {
			order.push("set-value");
			return 260;
		});
		if (value.get(1) != 4 || order.join(",") != "set-receiver,set-position,set-value")
			throw "Haxe Bytes set evaluation or masking behavior changed";

		final numeric = bytes([0, 0, 0, 0, 0, 0]);
		numeric.setUInt16(0, 0x12345);
		numeric.setInt32(2, -2);
		if (numeric.toHex() != "4523feffffff" || numeric.getUInt16(0) != 0x2345 || numeric.getInt32(2) != -2)
			throw "Haxe Bytes numeric byte order, masking, or signed result changed";
		final negativeUInt16 = bytes([0, 0]);
		negativeUInt16.setUInt16(0, -2);
		if (negativeUInt16.toHex() != "feff" || negativeUInt16.getUInt16(0) != 65534)
			throw "Haxe Bytes UInt16 negative write masking changed";
		if (bytes([0, 0, 0, 0x80]).getInt32(0) != -2147483648)
			throw "Haxe Bytes Int32 sign behavior changed";

		order.resize(0);
		final orderedUInt16 = getUInt16InSourceOrder(() -> {
			order.push("uint16-receiver");
			return bytes([0x12, 0x34]);
		}, () -> {
			order.push("uint16-position");
			return 0;
		});
		if (orderedUInt16 != 0x3412 || order.join(",") != "uint16-receiver,uint16-position")
			throw "Haxe Bytes UInt16 evaluation order changed";

		order.resize(0);
		final orderedInt32 = bytes([0, 0, 0, 0]);
		setInt32InSourceOrder(() -> {
			order.push("int32-receiver");
			return orderedInt32;
		}, () -> {
			order.push("int32-position");
			return 0;
		}, () -> {
			order.push("int32-value");
			return 0x12345678;
		});
		if (orderedInt32.toHex() != "78563412" || order.join(",") != "int32-receiver,int32-position,int32-value")
			throw "Haxe Bytes Int32 evaluation order changed";

		final int64Bytes = Bytes.alloc(8);
		final int64Value = haxe.Int64.make(0x12345678, -1985229329);
		int64Bytes.setInt64(0, int64Value);
		final int64Read = int64Bytes.getInt64(0);
		if (int64Bytes.toHex() != "efcdab8978563412" || int64Read.high != 0x12345678 || int64Read.low != -1985229329)
			throw "Haxe Bytes Int64 word order or bit preservation changed";

		order.resize(0);
		final orderedInt64Read = getInt64InSourceOrder(() -> {
			order.push("int64-get-receiver");
			return int64Bytes;
		}, () -> {
			order.push("int64-get-position");
			return 0;
		});
		if (orderedInt64Read.high != 0x12345678
			|| orderedInt64Read.low != -1985229329
			|| order.join(",") != "int64-get-receiver,int64-get-position") {
			throw "Haxe Bytes Int64 read evaluation order changed";
		}

		order.resize(0);
		final orderedInt64Write = Bytes.alloc(8);
		setInt64InSourceOrder(() -> {
			order.push("int64-set-receiver");
			return orderedInt64Write;
		}, () -> {
			order.push("int64-set-position");
			return 0;
		}, () -> {
			order.push("int64-set-value");
			return haxe.Int64.make(-1985229329, 0x01234567);
		});
		if (orderedInt64Write.toHex() != "67452301efcdab89"
			|| order.join(",") != "int64-set-receiver,int64-set-position,int64-set-value") {
			throw "Haxe Bytes Int64 write evaluation order changed";
		}

		order.resize(0);
		final data = getDataInSourceOrder(() -> {
			order.push("data-receiver");
			return value;
		});
		final fast = fastGetInSourceOrder(() -> {
			order.push("fast-data");
			return data;
		}, () -> {
			order.push("fast-position");
			return 1;
		});
		if (fast != 4 || order.join(",") != "data-receiver,fast-data,fast-position")
			throw "Haxe Bytes data/fastGet evaluation or value behavior changed";

		final alias = Bytes.ofData(data);
		value.set(0, 9);
		alias.set(2, 7);
		if (alias.get(0) != 9 || value.get(2) != 7)
			throw "Haxe BytesData stopped sharing mutable storage";

		expectFailure("Null Access", () -> getNullablePosition(value, null));
		expectFailure("Null Access", () -> setNullableValue(value, value.length, null));
		expectFailure("OutsideBounds", () -> numeric.getUInt16(numeric.length - 1));
		expectFailure("OutsideBounds", () -> numeric.setUInt16(numeric.length - 1, 1));
		expectFailure("OutsideBounds", () -> numeric.getInt32(numeric.length - 3));
		expectFailure("OutsideBounds", () -> numeric.setInt32(numeric.length - 3, 1));
		expectFailure("OutsideBounds", () -> int64Bytes.getInt64(1));
		expectFailure("OutsideBounds", () -> int64Bytes.setInt64(1, int64Value));
		Sys.println("HAXE_4_3_7_BYTES_ACCESS_ORACLE:PASS");
	}
}

class BytesAccessLookalike {
	public function new() {}

	public function get(position:Int):Int {
		return 0;
	}

	public function set(position:Int, value:Int):Void {}

	public function getData():BytesAccessLookalike {
		return this;
	}

	public function fastGet(data:BytesAccessLookalike, position:Int):Int {
		return 0;
	}
}
