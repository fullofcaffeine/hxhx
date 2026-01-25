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
	public function getString(pos:Int, len:Int, ?encoding:Encoding):String;
	public function toString():String;

	public function getData():BytesData;

	public static function alloc(length:Int):Bytes;
	public static function ofString(s:String, ?encoding:Encoding):Bytes;
	public static function ofData(b:BytesData):Bytes;
}
