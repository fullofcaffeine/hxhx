package;

import haxe.io.Bytes;
import haxe.io.BytesData;

/**
	Typed target inputs and Haxe 4.3.7 behavior cases for byte access.

	The macro fixture observes the target-selected declarations. Running this
	class directly exercises upstream Haxe's public behavior: evaluation order,
	unsigned byte values, low-byte masking, shared data, and nullable-argument
	conversion. The target runtime fixture separately proves reflaxe.ocaml's
	deterministic checked-bounds policy.
**/
class BytesAccessCases {
	static function bytes(values:Array<Int>):Bytes {
		final result = Bytes.alloc(values.length);
		for (index in 0...values.length)
			result.set(index, values[index]);
		return result;
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

		try {
			getNullablePosition(value, null);
			throw "expected Null Access";
		} catch (error:Dynamic) {
			if (Std.string(error) != "Null Access")
				throw error;
		}
		try {
			setNullableValue(value, value.length, null);
			throw "expected Null Access";
		} catch (error:Dynamic) {
			if (Std.string(error) != "Null Access")
				throw error;
		}
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
