package sys.io;

import haxe.io.Bytes;
import haxe.io.Output;

/**
	OCaml target implementation of `sys.io.FileOutput`.

	Why
	- Upstream unit/stdlib fixtures expect `sys.io.File.write/append/update` to return a stream
	  that supports seeking and position queries.

	What
	- Wraps an OCaml `out_channel` handle (opaque to Haxe) and implements `Output`:
	  - `writeByte` (and therefore `writeBytes`, `writeString`, etc.)
	  - `seek`, `tell`
	  - `flush`, `close`

	How
	- The handle is created by `sys.io.File.write/append/update` via `HxFileStream.open_out`.
	- All primitive operations are forwarded to `HxFileStream` via `@:native` externs.
**/
class FileOutput extends Output {
	final h:Dynamic;

	public function new(h:Dynamic) {
		this.h = h;
	}

	public override function close():Void {
		NativeHxFileStream.close_out(h);
	}

	public override function flush():Void {
		NativeHxFileStream.flush_out(h);
	}

	public override function writeByte(c:Int):Void {
		NativeHxFileStream.write_byte(h, c);
	}

	public override function writeBytes(buf:Bytes, pos:Int, len:Int):Int {
		if (len <= 0)
			return 0;
		for (i in 0...len) {
			writeByte(buf.get(pos + i));
		}
		return len;
	}

	public function seek(p:Int, pos:FileSeek):Void {
		NativeHxFileStream.seek_out(h, p, seekKind(pos));
	}

	public function tell():Int {
		return NativeHxFileStream.tell_out(h);
	}

	static inline function seekKind(pos:FileSeek):Int {
		return switch (pos) {
			case SeekBegin: 0;
			case SeekCur: 1;
			case SeekEnd: 2;
		}
	}
}

@:native("HxFileStream")
private extern class NativeHxFileStream {
	static function close_out(h:Dynamic):Void;
	static function flush_out(h:Dynamic):Void;
	static function write_byte(h:Dynamic, byte:Int):Void;
	static function seek_out(h:Dynamic, p:Int, kind:Int):Void;
	static function tell_out(h:Dynamic):Int;
}
