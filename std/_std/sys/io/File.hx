package sys.io;

/**
	OCaml target override for `sys.io.File`.

	This keeps the Haxe API stable, while the OCaml backend emits runtime calls
	(`HxFile`) for the supported primitives (whole-file reads/writes + copy).
**/
extern class File {
	static function getContent(path:String):String;
	static function saveContent(path:String, content:String):Void;
	static function getBytes(path:String):haxe.io.Bytes;
	static function saveBytes(path:String, bytes:haxe.io.Bytes):Void;

	static function read(path:String, binary:Bool = true):FileInput;
	static function write(path:String, binary:Bool = true):FileOutput;
	static function append(path:String, binary:Bool = true):FileOutput;
	static function update(path:String, binary:Bool = true):FileOutput;

	static function copy(srcPath:String, dstPath:String):Void;
}

