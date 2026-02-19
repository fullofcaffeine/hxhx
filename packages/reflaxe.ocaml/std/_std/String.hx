/**
	OCaml target override for `String`.

	This is a portable declaration surface: the OCaml backend lowers supported
	String operations to `HxString` runtime helpers.
**/
extern class String {
	public var length(default, null):Int;

	public function new(string:String):Void;

	public function toUpperCase():String;
	public function toLowerCase():String;
	public function charAt(index:Int):String;
	public function charCodeAt(index:Int):Null<Int>;
	public function indexOf(str:String, ?startIndex:Int):Int;
	public function lastIndexOf(str:String, ?startIndex:Int):Int;
	public function split(delimiter:String):Array<String>;
	public function substr(pos:Int, ?len:Int):String;
	public function substring(startIndex:Int, ?endIndex:Int):String;
	public function toString():String;

	@:pure public static function fromCharCode(code:Int):String;
}
