import haxe.io.Bytes;
import haxe.io.BytesData;
import haxe.io.Encoding;

/**
	Exercises the public Bytes API and the stdlib-only constructor contract.

	The constructor checks prove that the OCaml carrier preserves an explicit
	Haxe length separately from its aliased native data.
**/
@:access(haxe.io.Bytes)
class BytesMain {
	static final evaluationOrder:Array<String> = [];

	static function orderedBytes():Bytes {
		evaluationOrder.push("receiver");
		return Bytes.ofString("abcd");
	}

	static function orderedBytesValue(label:String, value:Bytes):Bytes {
		evaluationOrder.push(label);
		return value;
	}

	static function orderedNullableBytesValue(label:String, value:Null<Bytes>):Null<Bytes> {
		evaluationOrder.push(label);
		return value;
	}

	static function orderedInt(label:String, value:Int):Int {
		evaluationOrder.push(label);
		return value;
	}

	static function orderedInt64(label:String, value:haxe.Int64):haxe.Int64 {
		evaluationOrder.push(label);
		return value;
	}

	static function orderedData(label:String, value:BytesData):BytesData {
		evaluationOrder.push(label);
		return value;
	}

	static function nullInt():Null<Int> {
		return null;
	}

	static function bytes(values:Array<Int>):Bytes {
		final result = Bytes.alloc(values.length);
		for (index in 0...values.length)
			result.set(index, values[index]);
		return result;
	}

	static function byteValues(value:Bytes):String {
		return [for (index in 0...value.length) value.get(index)].join(",");
	}

	static function expectOutsideBounds(operation:Void->Void):Void {
		var failed = false;
		try {
			operation();
		} catch (error:Dynamic) {
			failed = Std.string(error) == "OutsideBounds";
		}
		if (!failed)
			throw "expected OutsideBounds";
	}

	static function main() {
		var b = Bytes.ofString("xxxxxx");
		if (b.length != 6)
			throw "unexpected";

		var src = Bytes.ofString("abc");
		b.blit(1, src, 0, 3);
		if (b.toString() != "xabcxx")
			throw "unexpected";

		var a = "a".charCodeAt(0);
		if (b.get(1) != a)
			throw "unexpected";

		evaluationOrder.resize(0);
		final accessed = orderedBytesValue("get-receiver", b).get(orderedInt("get-position", 1));
		if (accessed != a || evaluationOrder.join(",") != "get-receiver,get-position")
			throw "Bytes get evaluation order changed";

		evaluationOrder.resize(0);
		orderedBytesValue("set-receiver", b).set(orderedInt("set-position", 0), orderedInt("set-value", 378));
		if (b.get(0) != 122 || evaluationOrder.join(",") != "set-receiver,set-position,set-value")
			throw "Bytes set evaluation or low-byte masking changed";

		var sub = b.sub(1, 3);
		if (sub.toString() != "abc")
			throw "unexpected";
		if (sub.compare(src) != 0)
			throw "unexpected";

		if (b.getString(1, 3) != "abc")
			throw "unexpected";
		if (b.getString(1, 3, Encoding.UTF8) != "abc" || b.getString(1, 3, Encoding.RawNative) != "abc")
			throw "unexpected explicit encoding";

		evaluationOrder.resize(0);
		final ordered = orderedBytes().sub(orderedInt("position", 1), orderedInt("length", 2));
		if (ordered.toString() != "bc" || evaluationOrder.join(",") != "receiver,position,length")
			throw "Bytes read evaluation order changed";

		evaluationOrder.resize(0);
		final nullableOrdered = orderedNullableBytesValue("nullable-receiver",
			Bytes.ofString("abcd")).sub(orderedInt("nullable-position", 1), orderedInt("nullable-length", 2));
		if (nullableOrdered.toString() != "bc" || evaluationOrder.join(",") != "nullable-receiver,nullable-position,nullable-length") {
			throw "nullable Bytes read evaluation order changed";
		}

		evaluationOrder.resize(0);
		var nullableReceiverFailedBeforeArguments = false;
		try {
			orderedNullableBytesValue("nullable-null-receiver",
				null).getString(orderedInt("unexpected-position", 0), orderedInt("unexpected-length", 0), Encoding.UTF8);
		} catch (error:Dynamic) {
			nullableReceiverFailedBeforeArguments = Std.string(error) == "Null Access";
		}
		if (!nullableReceiverFailedBeforeArguments || evaluationOrder.join(",") != "nullable-null-receiver")
			throw "nullable Bytes receiver did not fail before argument evaluation";

		var filled = Bytes.alloc(4);
		filled.fill(0, 4, "A".charCodeAt(0));
		if (filled.toString() != "AAAA")
			throw "unexpected";
		evaluationOrder.resize(0);
		final orderedFill = bytes([0, 1, 2, 3, 4, 5]);
		orderedBytesValue("fill-receiver", orderedFill).fill(orderedInt("fill-position", 1), orderedInt("fill-length", 3), orderedInt("fill-value", 260));
		if (evaluationOrder.join(",") != "fill-receiver,fill-position,fill-length,fill-value" || byteValues(orderedFill) != "0,4,4,4,4,5")
			throw "Bytes fill evaluation or byte masking changed";

		evaluationOrder.resize(0);
		final orderedBlit = bytes([0, 1, 2, 3, 4, 5]);
		final orderedSource = bytes([10, 11, 12, 13, 14, 15]);
		orderedBytesValue("blit-receiver",
			orderedBlit).blit(orderedInt("blit-position", 1), orderedBytesValue("blit-source", orderedSource), orderedInt("blit-source-position", 2),
				orderedInt("blit-length", 3));
		if (evaluationOrder.join(",") != "blit-receiver,blit-position,blit-source,blit-source-position,blit-length"
			|| byteValues(orderedBlit) != "0,12,13,14,4,5"
			|| byteValues(orderedSource) != "10,11,12,13,14,15") {
			throw "Bytes blit evaluation or source behavior changed";
		}

		final forward = bytes([0, 1, 2, 3, 4, 5]);
		forward.blit(1, forward, 0, 5);
		final backward = bytes([0, 1, 2, 3, 4, 5]);
		backward.blit(0, backward, 1, 5);
		if (byteValues(forward) != "0,0,1,2,3,4" || byteValues(backward) != "1,2,3,4,5,5")
			throw "Bytes overlapping blit behavior changed";

		var nullAccess = false;
		try {
			filled.fill(0, 1, nullInt());
		} catch (error:Dynamic) {
			nullAccess = Std.string(error) == "Null Access";
		}
		if (!nullAccess)
			throw "Bytes fill accepted a null Int";

		final data = Bytes.ofString("abc").getData();
		evaluationOrder.resize(0);
		final orderedDataAlias = orderedBytesValue("data-receiver", Bytes.ofString("abc")).getData();
		final orderedFast = Bytes.fastGet(orderedData("fast-data", orderedDataAlias), orderedInt("fast-position", 1));
		if (orderedFast != "b".charCodeAt(0) || evaluationOrder.join(",") != "data-receiver,fast-data,fast-position")
			throw "Bytes getData/fastGet evaluation order changed";
		final declaredShort = new Bytes(1, data);
		if (declaredShort.length != 1 || declaredShort.toString() != "a")
			throw "explicit Bytes length was not preserved";
		declaredShort.set(0, "z".charCodeAt(0));
		final dataAlias = Bytes.ofData(data);
		if (dataAlias.length != 3 || dataAlias.toString() != "zbc" || Bytes.fastGet(data, 0) != "z".charCodeAt(0))
			throw "Bytes data alias was not preserved";

		var outsideDeclaredLength = false;
		try {
			declaredShort.get(1);
		} catch (_) {
			outsideDeclaredLength = true;
		}
		if (!outsideDeclaredLength)
			throw "Bytes access ignored the declared length";

		var nullableSetFailedBeforeBounds = false;
		try {
			declaredShort.set(declaredShort.length, nullInt());
		} catch (error:Dynamic) {
			nullableSetFailedBeforeBounds = Std.string(error) == "Null Access";
		}
		if (!nullableSetFailedBeforeBounds)
			throw "Bytes set did not preserve nullable Int conversion before range validation";

		var outsideNativeData = false;
		try {
			Bytes.fastGet(data, dataAlias.length);
		} catch (error:Dynamic) {
			outsideNativeData = Std.string(error) == "OutsideBounds";
		}
		if (!outsideNativeData)
			throw "Bytes fastGet did not apply the declared OCaml target bounds policy";

		var outsideMutationRange = false;
		try {
			declaredShort.blit(1, dataAlias, 0, 1);
		} catch (error:Dynamic) {
			outsideMutationRange = Std.string(error) == "OutsideBounds";
		}
		if (!outsideMutationRange)
			throw "Bytes mutation ignored the declared length";

		final numeric = Bytes.alloc(10);
		numeric.setUInt16(0, 0x12345);
		numeric.setInt32(2, -2);
		numeric.setInt32(6, 0x12345678);
		if (numeric.toHex() != "4523feffffff78563412"
			|| numeric.getUInt16(0) != 0x2345
			|| numeric.getInt32(2) != -2
			|| numeric.getInt32(6) != 0x12345678) {
			throw "Bytes numeric byte order, masking, signed result, or hexadecimal output changed";
		}
		final negativeUInt16 = Bytes.alloc(2);
		negativeUInt16.setUInt16(0, -2);
		if (negativeUInt16.toHex() != "feff" || negativeUInt16.getUInt16(0) != 65534)
			throw "Bytes UInt16 negative write masking changed";

		evaluationOrder.resize(0);
		final orderedUInt16 = orderedBytesValue("uint16-receiver", numeric).getUInt16(orderedInt("uint16-position", 0));
		if (orderedUInt16 != 0x2345 || evaluationOrder.join(",") != "uint16-receiver,uint16-position")
			throw "Bytes UInt16 evaluation order changed";

		evaluationOrder.resize(0);
		orderedBytesValue("int32-receiver", numeric).setInt32(orderedInt("int32-position", 6), orderedInt("int32-value", -2));
		if (numeric.getInt32(6) != -2 || evaluationOrder.join(",") != "int32-receiver,int32-position,int32-value")
			throw "Bytes Int32 evaluation order changed";

		final int64Bytes = Bytes.alloc(8);
		final int64Value = haxe.Int64.make(0x12345678, -1985229329);
		evaluationOrder.resize(0);
		orderedBytesValue("int64-set-receiver", int64Bytes).setInt64(orderedInt("int64-set-position", 0), orderedInt64("int64-set-value", int64Value));
		if (int64Bytes.toHex() != "efcdab8978563412"
			|| evaluationOrder.join(",") != "int64-set-receiver,int64-set-position,int64-set-value") {
			throw "Bytes Int64 write order, bits, or evaluation order changed";
		}

		evaluationOrder.resize(0);
		final int64Read = orderedBytesValue("int64-get-receiver", int64Bytes).getInt64(orderedInt("int64-get-position", 0));
		if (int64Read.high != 0x12345678
			|| int64Read.low != -1985229329
			|| evaluationOrder.join(",") != "int64-get-receiver,int64-get-position") {
			throw "Bytes Int64 read order, bits, or evaluation order changed";
		}

		expectOutsideBounds(() -> numeric.getUInt16(numeric.length - 1));
		expectOutsideBounds(() -> numeric.setUInt16(numeric.length - 1, 1));
		expectOutsideBounds(() -> numeric.getInt32(numeric.length - 3));
		expectOutsideBounds(() -> numeric.setInt32(numeric.length - 3, 1));
		expectOutsideBounds(() -> int64Bytes.getInt64(1));
		expectOutsideBounds(() -> int64Bytes.setInt64(1, int64Value));
	}
}
