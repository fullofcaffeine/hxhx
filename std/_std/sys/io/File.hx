package sys.io;

import haxe.io.Bytes;

/**
	OCaml target override for `sys.io.File`.

	Why
	- The upstream `sys.io.File` API is `extern` and requires target/runtime support.
	- For OCaml we want a portable surface that "just works" for common tooling workloads
	  (read/write files, streams, copy) while emitting idiomatic OCaml and integrating
	  with dune.

	What
	- Whole-file APIs:
	  - `getContent` / `saveContent`
	  - `getBytes` / `saveBytes`
	  - `copy`
	- Stream APIs:
	  - `read` / `write` / `append` / `update` returning `FileInput` / `FileOutput`

	How
	- Implemented as a small Haxe wrapper around tiny OCaml runtime helpers:
	  - `HxFile` (whole-file ops)
	  - `HxFileStream` (stream open/seek/tell/read/write)

	Notes
	- This is correctness-first and intentionally minimal. Performance improvements (buffered
	  reads/writes, vectored IO) can come later once semantics are locked down.
**/
class File {
	public static inline function getContent(path:String):String {
		return NativeHxFile.getContent(path);
	}

	public static inline function saveContent(path:String, content:String):Void {
		NativeHxFile.saveContent(path, content);
	}

	public static inline function getBytes(path:String):Bytes {
		return Bytes.ofData(NativeHxFile.getBytes(path));
	}

	public static inline function saveBytes(path:String, bytes:Bytes):Void {
		NativeHxFile.saveBytes(path, bytes.getData());
	}

	public static inline function copy(srcPath:String, dstPath:String):Void {
		NativeHxFile.copy(srcPath, dstPath);
	}

	public static function read(path:String, binary:Bool = true):FileInput {
		return new FileInput(NativeHxFileStream.open_in(path, binary));
	}

	public static function write(path:String, binary:Bool = true):FileOutput {
		return new FileOutput(NativeHxFileStream.open_out(path, binary, false, false));
	}

	public static function append(path:String, binary:Bool = true):FileOutput {
		return new FileOutput(NativeHxFileStream.open_out(path, binary, true, false));
	}

	public static function update(path:String, binary:Bool = true):FileOutput {
		return new FileOutput(NativeHxFileStream.open_out(path, binary, false, true));
	}
}

@:native("HxFile")
private extern class NativeHxFile {
	static function getContent(path:String):String;
	static function saveContent(path:String, content:String):Void;
	static function getBytes(path:String):Dynamic;
	static function saveBytes(path:String, bytes:Dynamic):Void;
	static function copy(srcPath:String, dstPath:String):Void;
}

@:native("HxFileStream")
private extern class NativeHxFileStream {
	static function open_in(path:String, binary:Bool):Dynamic;
	/**
		Open an output stream.

		- `append = true` opens the stream in append mode.
		- `update = true` opens without truncating (best-effort "update" semantics).
	**/
	static function open_out(path:String, binary:Bool, append:Bool, update:Bool):Dynamic;
}

