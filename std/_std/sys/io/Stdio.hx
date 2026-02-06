package sys.io;

import haxe.io.Bytes;
import haxe.io.Encoding;
import haxe.io.Eof;
import haxe.io.Input;
import haxe.io.Output;

/**
	OCaml target support for `Sys.stdin()`, `Sys.stdout()`, and `Sys.stderr()`.

	Why
	- `Sys.stdin/stdout/stderr` are a core part of Haxe's portable stdlib surface.
	- The OCaml backend needs a way to do stream IO without requiring `__ocaml__`
	  escape hatches in user code.

	What
	- `stdin()` returns an `Input` backed by the OCaml process stdin.
	- `stdout()` / `stderr()` return `Output` values backed by the OCaml process
	  stdout/stderr with explicit `flush()` support.

	How
	- This class is an OCaml-target-only std override. It uses a small OCaml runtime
	  shim (`std/runtime/HxStdio.ml`) for byte/line IO and flushing.
	- The compiler backend lowers:
	  - `Sys.stdin()` → `sys.io.Stdio.stdin()`
	  - `Sys.stdout()` → `sys.io.Stdio.stdout()`
	  - `Sys.stderr()` → `sys.io.Stdio.stderr()`

	Notes
	- We currently create a new wrapper instance on each call. That keeps us
	  independent from "mutable static field" lowering while it is still evolving.
	  (Caching can be added later once static reassignment semantics are defined.)
**/
@:keep
class Stdio {
	static inline final STREAM_STDIN:Int = 0;
	static inline final STREAM_STDOUT:Int = 1;
	static inline final STREAM_STDERR:Int = 2;

	public static function stdin():Input {
		return new OcamlStdioInput(STREAM_STDIN);
	}

	public static function stdout():Output {
		return new OcamlStdioOutput(STREAM_STDOUT);
	}

	public static function stderr():Output {
		return new OcamlStdioOutput(STREAM_STDERR);
	}
}

	private class OcamlStdioInput extends Input {
		final stream:Int;

		public function new(stream:Int) {
			this.stream = stream;
		}

	public override function readByte():Int {
		final b = NativeHxStdio.read_byte(stream);
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

	public override function readLine():String {
		// Prefer a native line reader to avoid per-byte overhead in common tooling workloads.
		final s = NativeHxStdio.read_line(stream);
		if (s == null) throw new Eof();
		return s;
	}
}

	private class OcamlStdioOutput extends Output {
		final stream:Int;

		public function new(stream:Int) {
			this.stream = stream;
		}

	public override function writeByte(c:Int):Void {
		NativeHxStdio.write_byte(stream, c);
	}

	public override function writeBytes(buf:Bytes, pos:Int, len:Int):Int {
		if (len <= 0) return 0;
		for (i in 0...len) {
			writeByte(buf.get(pos + i));
		}
		return len;
	}

	public override function writeString(s:String, ?encoding:Encoding):Void {
		if (encoding != null) {}
		if (s == null || s.length == 0) return;
		NativeHxStdio.write_string(stream, s);
	}

	public override function flush():Void {
		NativeHxStdio.flush(stream);
	}
}

@:native("HxStdio")
private extern class NativeHxStdio {
	static function read_byte(stream:Int):Int;
	static function read_line(stream:Int):Null<String>;
	static function write_byte(stream:Int, byte:Int):Void;
	static function write_string(stream:Int, s:String):Void;
	static function flush(stream:Int):Void;
}
