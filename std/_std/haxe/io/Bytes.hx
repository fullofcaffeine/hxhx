package haxe.io;

/**
 * OCaml target override for `haxe.io.Bytes`.
 *
 * This is an extern surface: codegen maps calls to `HxBytes` runtime helpers.
 */
extern class Bytes {
	public var length(default, null):Int;

	/**
		Internal constructor used by some stdlib code (e.g. `haxe.io.BytesBuffer`)
		inside `untyped` blocks.

		We keep this declared so Haxe can type/resolve `new Bytes(len, data)`
		even though the OCaml backend ultimately maps this to runtime helpers.
	**/
	private function new(length:Int, b:BytesData);

	public function get(pos:Int):Int;
	public function set(pos:Int, v:Int):Void;
	public function blit(pos:Int, src:Bytes, srcpos:Int, len:Int):Void;
	public function fill(pos:Int, len:Int, value:Int):Void;
	public function sub(pos:Int, len:Int):Bytes;
	public function compare(other:Bytes):Int;
	public function getDouble(pos:Int):Float;
	public function getFloat(pos:Int):Float;
	public function setDouble(pos:Int, v:Float):Void;
	public function setFloat(pos:Int, v:Float):Void;
	public function getUInt16(pos:Int):Int;
	public function setUInt16(pos:Int, v:Int):Void;
	public function getInt32(pos:Int):Int;
	public function setInt32(pos:Int, v:Int):Void;
	public function getInt64(pos:Int):haxe.Int64;
	public function setInt64(pos:Int, v:haxe.Int64):Void;
	public function getString(pos:Int, len:Int, ?encoding:Encoding):String;
	public function toString():String;
	public function toHex():String;

	public function getData():BytesData;

	public static function alloc(length:Int):Bytes;
	public static function ofString(s:String, ?encoding:Encoding):Bytes;
	public static function ofData(b:BytesData):Bytes;
	public static function ofHex(s:String):Bytes;

	/**
		Fast byte access helper used by upstream stdlib (e.g. `haxe.crypto.Crc32`).

		Why
		- Upstream stdlib uses `Bytes.fastGet` for tight loops where bounds checks would be costly.
		- Even if our backend does not (yet) lower this to an unsafe primitive, we must still
		  provide the API surface so upstream code types correctly.

		How
		- The OCaml backend lowers this call to `HxBytes.get` for now (bounds-checked).
		- Once we have a safe/unsafe split in the runtime, we can map this to an unchecked
		  read to better match upstream intent.
	**/
	public static function fastGet(b:BytesData, pos:Int):Int;
}
