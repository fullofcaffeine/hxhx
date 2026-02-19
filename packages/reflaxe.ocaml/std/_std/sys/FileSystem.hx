package sys;

/**
	OCaml target override for `sys.FileSystem`.

	This is a signature-only surface: the OCaml backend lowers calls to a small
	runtime shim (`HxFileSystem`) so portable Haxe code can use `sys.FileSystem`
	without being aware of OCaml's APIs.
**/
extern class FileSystem {
	static function exists(path:String):Bool;
	static function rename(path:String, newPath:String):Void;
	static function stat(path:String):FileStat;
	static function fullPath(relPath:String):String;
	static function absolutePath(relPath:String):String;
	static function isDirectory(path:String):Bool;
	static function createDirectory(path:String):Void;
	static function deleteFile(path:String):Void;
	static function deleteDirectory(path:String):Void;
	static function readDirectory(path:String):Array<String>;
}
