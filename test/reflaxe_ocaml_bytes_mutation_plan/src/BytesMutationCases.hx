package;

import haxe.io.Bytes;

/**
	Typed source and runtime-oracle cases for exact Bytes `fill` and `blit`.

	The runtime checks are portable Haxe 4.3.7 behavior. The macro fixture also
	inspects these final typed calls before reflaxe.ocaml constructs syntax.
**/
class BytesMutationCases {
	static function bytes(values:Array<Int>):Bytes {
		final result = Bytes.alloc(values.length);
		for (index in 0...values.length)
			result.set(index, values[index]);
		return result;
	}

	static function values(value:Bytes):String {
		return [for (index in 0...value.length) value.get(index)].join(",");
	}

	public static function fill(bytes:Bytes, position:Int, length:Int, value:Int):Void {
		bytes.fill(position, length, value);
	}

	public static function fillNullableValue(bytes:Bytes, position:Int, value:Null<Int>):Void {
		bytes.fill(position, 1, value);
	}

	public static function blit(destination:Bytes, position:Int, source:Bytes, sourcePosition:Int, length:Int):Void {
		destination.blit(position, source, sourcePosition, length);
	}

	public static function fillInSourceOrder(receiver:Void->Bytes, position:Void->Int, length:Void->Int, value:Void->Int):Void {
		receiver().fill(position(), length(), value());
	}

	public static function blitInSourceOrder(receiver:Void->Bytes, position:Void->Int, source:Void->Bytes, sourcePosition:Void->Int, length:Void->Int):Void {
		receiver().blit(position(), source(), sourcePosition(), length());
	}

	public static function userLookalike(value:BytesMutationLookalike):Void {
		value.fill(0, 1, 2);
		value.blit(0, value, 0, 1);
	}

	static function expectOutsideBounds(operation:Void->Void):Void {
		try {
			operation();
			throw "expected OutsideBounds";
		} catch (error:Dynamic) {
			if (Std.string(error) != "OutsideBounds")
				throw error;
		}
	}

	public static function main():Void {
		final order:Array<String> = [];
		final destination = bytes([0, 1, 2, 3, 4, 5]);
		fillInSourceOrder(() -> {
			order.push("fill-receiver");
			return destination;
		}, () -> {
			order.push("fill-position");
			return 1;
		}, () -> {
			order.push("fill-length");
			return 3;
		}, () -> {
			order.push("fill-value");
			return 260;
		});
		if (order.join(",") != "fill-receiver,fill-position,fill-length,fill-value" || values(destination) != "0,4,4,4,4,5")
			throw "Haxe Bytes fill behavior changed";

		order.resize(0);
		final blitDestination = bytes([0, 1, 2, 3, 4, 5]);
		final source = bytes([10, 11, 12, 13, 14, 15]);
		blitInSourceOrder(() -> {
			order.push("blit-receiver");
			return blitDestination;
		}, () -> {
			order.push("blit-position");
			return 1;
		}, () -> {
			order.push("blit-source");
			return source;
		}, () -> {
			order.push("blit-source-position");
			return 2;
		}, () -> {
			order.push("blit-length");
			return 3;
		});
		if (order.join(",") != "blit-receiver,blit-position,blit-source,blit-source-position,blit-length"
			|| values(blitDestination) != "0,12,13,14,4,5"
			|| values(source) != "10,11,12,13,14,15") {
			throw "Haxe Bytes blit behavior changed";
		}

		final forward = bytes([0, 1, 2, 3, 4, 5]);
		forward.blit(1, forward, 0, 5);
		final backward = bytes([0, 1, 2, 3, 4, 5]);
		backward.blit(0, backward, 1, 5);
		if (values(forward) != "0,0,1,2,3,4" || values(backward) != "1,2,3,4,5,5")
			throw "Haxe Bytes overlapping blit behavior changed";

		expectOutsideBounds(() -> bytes([0]).fill(1, 1, 7));
		expectOutsideBounds(() -> bytes([0]).blit(1, bytes([1]), 0, 1));
		expectOutsideBounds(() -> bytes([0]).blit(0, bytes([1]), 1, 1));
		try {
			fillNullableValue(bytes([0]), 1, null);
			throw "expected Null Access";
		} catch (error:Dynamic) {
			if (Std.string(error) != "Null Access")
				throw error;
		}
		Sys.println("HAXE_4_3_7_BYTES_MUTATION_ORACLE:PASS");
	}
}

class BytesMutationLookalike {
	public function new() {}

	public function fill(position:Int, length:Int, value:Int):Void {}

	public function blit(position:Int, source:BytesMutationLookalike, sourcePosition:Int, length:Int):Void {}
}
