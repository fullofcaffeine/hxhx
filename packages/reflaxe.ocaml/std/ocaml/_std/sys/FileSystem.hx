package sys;

/**
	OCaml target override for `sys.FileSystem`.

	The extern keeps the portable Haxe API while its checked target metadata
	maps every operation to the small `HxFileSystem` runtime module. Packaging
	can therefore use the typed Haxe declaration instead of inferring the
	dependency from generated OCaml syntax.
**/
@:ocamlRuntime("haxe-file-system")
@:native("HxFileSystem")
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
