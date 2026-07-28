package;

import haxe.io.Bytes;
import haxe.io.BytesData;
import haxe.io.Encoding;

typedef BytesAlias = Bytes;
abstract BytesWrapper(Bytes) from Bytes to Bytes {}

/**
	Typed source forms used by the Bytes producer-plan invariant fixture.

	These functions are never executed. The macro test reads their final typed
	expressions so the planner is checked against the real Haxe 4.3.7 API shape.
**/
@:access(haxe.io.Bytes)
class BytesProducerCases {
	public static function internalConstructor(length:Int, data:haxe.io.BytesData):Bytes {
		return new Bytes(length, data);
	}

	public static function alloc(length:Int):Bytes {
		return Bytes.alloc(length);
	}

	public static function ofStringDefault(value:String):Bytes {
		return Bytes.ofString(value);
	}

	public static function ofStringExplicitNull(value:String):Bytes {
		return Bytes.ofString(value, null);
	}

	public static function ofStringUtf8(value:String):Bytes {
		return Bytes.ofString(value, Encoding.UTF8);
	}

	public static function ofStringRawNative(value:String):Bytes {
		return Bytes.ofString(value, Encoding.RawNative);
	}

	public static function ofData(data:BytesData):Bytes {
		return Bytes.ofData(data);
	}

	public static function ofHex(value:String):Bytes {
		return Bytes.ofHex(value);
	}
}
