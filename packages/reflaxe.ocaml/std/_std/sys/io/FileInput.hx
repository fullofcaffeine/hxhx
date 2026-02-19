package sys.io;

import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;

/**
	OCaml target implementation of `sys.io.FileInput`.

	Why
	- Many upstream unit/stdlib workloads use the stream API (`File.read`, `seek`, `tell`, `eof`)
	  rather than whole-file IO.
	- For native targets we want `--interp`-style workflows (compile → run) to behave the same
	  as other platforms.

	What
	- Wraps an OCaml `in_channel` handle (opaque to Haxe) and implements the `Input` contract:
	  - `readByte` (and therefore `readBytes`, `readAll`, etc.)
	  - `seek`, `tell`, `eof`
	  - `close`

	How
	- The handle is created by `sys.io.File.read` via `HxFileStream.open_in`.
	- All primitive operations are forwarded to `HxFileStream` via `@:native` externs.
**/
class FileInput extends Input {
	final h:Dynamic;

	public function new(h:Dynamic) {
		this.h = h;
	}

	public override function close():Void {
		NativeHxFileStream.close_in(h);
	}

	public override function readByte():Int {
		final b = NativeHxFileStream.read_byte(h);
		if (b < 0) throw new Eof();
		return b;
	}

	public override function readBytes(buf:Bytes, pos:Int, len:Int):Int {
		if (len <= 0) return 0;
		var i = 0;
		try {
			while (i < len) {
				buf.set(pos + i, readByte());
				i++;
			}
		} catch (_:Eof) {
			if (i == 0) throw new Eof();
		}
		return i;
	}

	public function seek(p:Int, pos:FileSeek):Void {
		NativeHxFileStream.seek_in(h, p, seekKind(pos));
	}

	public function tell():Int {
		return NativeHxFileStream.tell_in(h);
	}

	public function eof():Bool {
		return NativeHxFileStream.eof_in(h);
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
	static function close_in(h:Dynamic):Void;
	static function read_byte(h:Dynamic):Int;
	static function seek_in(h:Dynamic, p:Int, kind:Int):Void;
	static function tell_in(h:Dynamic):Int;
	static function eof_in(h:Dynamic):Bool;
}

