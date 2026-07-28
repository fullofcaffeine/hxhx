package;

import haxe.Int64;
import haxe.io.Bytes;
import haxe.io.BytesData;
import haxe.io.Encoding;

/**
	Typed source forms used by the exact Bytes read-plan fixture.

	The macro fixture inspects these final Haxe 4.3.7 typed expressions. The
	Float and Int64 methods are present specifically to prove that this bounded
	read family does not admit representations it cannot yet explain.
**/
class BytesReadCases {
	public static function main():Void {
		final order:Array<String> = [];
		final value = receiverAndArgumentsInSourceOrder(() -> {
			order.push("receiver");
			return Bytes.ofString("abcd");
		}, () -> {
			order.push("position");
			return 1;
		}, () -> {
			order.push("length");
			return 2;
		});
		if (order.join(",") != "receiver,position,length" || value.toString() != "bc")
			throw "Haxe Bytes read evaluation order changed";
		Sys.println("HAXE_4_3_7_BYTES_READ_ORDER_ORACLE:PASS");
	}

	public static function length(bytes:Bytes):Int {
		return bytes.length;
	}

	public static function fastGet(data:BytesData, position:Int):Int {
		return Bytes.fastGet(data, position);
	}

	public static function get(bytes:Bytes, position:Int):Int {
		return bytes.get(position);
	}

	public static function getUInt16(bytes:Bytes, position:Int):Int {
		return bytes.getUInt16(position);
	}

	public static function getInt32(bytes:Bytes, position:Int):Int {
		return bytes.getInt32(position);
	}

	public static function sub(bytes:Bytes, position:Int, length:Int):Bytes {
		return bytes.sub(position, length);
	}

	public static function compare(bytes:Bytes, other:Bytes):Int {
		return bytes.compare(other);
	}

	public static function getStringDefault(bytes:Bytes, position:Int, length:Int):String {
		return bytes.getString(position, length);
	}

	public static function getStringExplicitNull(bytes:Bytes, position:Int, length:Int):String {
		return bytes.getString(position, length, null);
	}

	public static function getStringUtf8(bytes:Bytes, position:Int, length:Int):String {
		return bytes.getString(position, length, Encoding.UTF8);
	}

	public static function getStringRawNative(bytes:Bytes, position:Int, length:Int):String {
		return bytes.getString(position, length, Encoding.RawNative);
	}

	public static function toString(bytes:Bytes):String {
		return bytes.toString();
	}

	public static function toHex(bytes:Bytes):String {
		return bytes.toHex();
	}

	public static function getData(bytes:Bytes):BytesData {
		return bytes.getData();
	}

	public static function receiverAndArgumentsInSourceOrder(receiver:Void->Bytes, position:Void->Int, length:Void->Int):Bytes {
		return receiver().sub(position(), length());
	}

	public static function deferredFloat(bytes:Bytes, position:Int):Float {
		return bytes.getFloat(position);
	}

	public static function deferredDouble(bytes:Bytes, position:Int):Float {
		return bytes.getDouble(position);
	}

	public static function deferredInt64(bytes:Bytes, position:Int):Int64 {
		return bytes.getInt64(position);
	}
}
