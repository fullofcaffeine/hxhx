import haxe.io.Bytes;
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

	static function orderedInt(label:String, value:Int):Int {
		evaluationOrder.push(label);
		return value;
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

		b.set(0, "z".charCodeAt(0));
		if (b.toString().charAt(0) != "z")
			throw "unexpected";

		var sub = b.sub(1, 3);
		if (sub.toString() != "abc")
			throw "unexpected";
		if (sub.compare(src) != 0)
			throw "unexpected";

		if (b.getString(1, 3) != "abc")
			throw "unexpected";
		if (b.getString(1, 3, Encoding.UTF8) != "abc" || b.getString(1, 3, Encoding.RawNative) != "abc")
			throw "unexpected explicit encoding";

		final ordered = orderedBytes().sub(orderedInt("position", 1), orderedInt("length", 2));
		if (ordered.toString() != "bc" || evaluationOrder.join(",") != "receiver,position,length")
			throw "Bytes read evaluation order changed";

		var filled = Bytes.alloc(4);
		filled.fill(0, 4, "A".charCodeAt(0));
		if (filled.toString() != "AAAA")
			throw "unexpected";

		final data = Bytes.ofString("abc").getData();
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

		final numeric = Bytes.alloc(4);
		numeric.set(0, 0x34);
		numeric.set(1, 0x12);
		numeric.set(2, 0x78);
		numeric.set(3, 0x56);
		if (numeric.getUInt16(0) != 0x1234 || numeric.getInt32(0) != 0x56781234 || numeric.toHex() != "34127856")
			throw "Bytes numeric or hexadecimal read changed";
	}
}
