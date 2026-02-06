package sys.io;

import haxe.io.Bytes;
import haxe.io.Encoding;
import haxe.io.Eof;
import haxe.io.Input;
import haxe.io.Output;

/**
	OCaml target override for `sys.io.Process`.

	Why
	- `hxhx` Stage 4 (native macros, Model A) needs a reliable way to:
	  - spawn a helper process (macro host),
	  - write requests to its stdin,
	  - read responses from its stdout/stderr,
	  - flush deterministically.
	- The OCaml target’s portable stdlib surface is still growing; relying on a
	  fully-featured, cross-target `sys.io.Process` implementation is premature.
	- Instead, we provide a **target-runtime shim** (`HxProcess.ml`) that exposes
	  minimal Unix process/pipes primitives, and implement the *Haxe* API here.

	What
	- Implements enough of the standard `sys.io.Process` shape to support:
	  - `stdout.readLine()` / `stderr.readLine()`
	  - `stdin.writeString(...)` + `stdin.flush()`
	  - `exitCode()` / `close()`
	  - best-effort `kill()`

	How
	- The low-level work is done by `std/runtime/HxProcess.ml`, accessed via the
	  `NativeHxProcess` extern below.

	Portability policy
	- This is an OCaml-target-only implementation. It exists so we can keep the
	  compiler + macro protocol logic in Haxe.
	- Long-term, we should reassess and retire this shim in favor of a pure-Haxe
	  implementation once the process APIs are stable across targets.
**/
	class Process {
		public var stdout(default, null):Input;
		public var stderr(default, null):Input;
		public var stdin(default, null):Output;

		final handle:Int;
		var closed:Bool = false;
		var cachedExitCode:Null<Int> = null;

		public function new(cmd:String, ?args:Array<String>, ?detached:Bool) {
			final argv = args == null ? [] : args;
			// NOTE: We accept `detached` for upstream signature parity, but currently ignore it.
			// Implementing true detachment is target-specific (process groups) and not required
			// for our current macro-host transport needs.
			if (detached != null) {}
			handle = NativeHxProcess.spawn(cmd, argv);
			stdout = new OcamlProcessInput(handle, 1);
			stderr = new OcamlProcessInput(handle, 2);
			stdin = new OcamlProcessOutput(handle);
		}

	public function getPid():Int {
		// We don't currently expose the PID to Haxe in this shim.
		return -1;
	}

	public function kill():Void {
		if (closed) return;
		NativeHxProcess.kill(handle);
	}

	public function close():Void {
		if (closed) return;
		cachedExitCode = NativeHxProcess.close(handle);
		closed = true;
	}

	public function exitCode():Int {
		if (cachedExitCode != null) return cachedExitCode;
		close();
		return cachedExitCode == null ? 0 : cachedExitCode;
	}
}

/**
	`haxe.io.Input` implementation backed by `HxProcess` channels.

	This is intentionally minimal; we implement `readByte`, `readBytes`, and
	`readLine` as those are the operations exercised by our macro-host transport.
**/
	private class OcamlProcessInput extends Input {
	final handle:Int;
	final stream:Int;

		public function new(handle:Int, stream:Int) {
			this.handle = handle;
			this.stream = stream;
		}

	public override function readByte():Int {
		final b = NativeHxProcess.read_byte(handle, stream);
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
		final s = NativeHxProcess.read_line(handle, stream);
		if (s == null) throw new Eof();
		return s;
	}
}

/**
	`haxe.io.Output` implementation backed by `HxProcess` stdin.
**/
	private class OcamlProcessOutput extends Output {
	final handle:Int;

		public function new(handle:Int) {
			this.handle = handle;
		}

	public override function writeByte(c:Int):Void {
		NativeHxProcess.write_byte(handle, c);
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
		NativeHxProcess.write_string(handle, s);
	}

	public override function flush():Void {
		NativeHxProcess.flush_stdin(handle);
	}
}

/**
	OCaml runtime shim used by `sys.io.Process` for the OCaml target.

	This is intentionally *not* a macro API: it is a tiny “process + pipes”
	service implemented in OCaml for correctness during early bootstrapping.
**/
	@:native("HxProcess")
	private extern class NativeHxProcess {
		static function spawn(cmd:String, args:Array<String>):Int;
		static function read_byte(handle:Int, stream:Int):Int;
		static function read_line(handle:Int, stream:Int):Null<String>;
		static function write_byte(handle:Int, byte:Int):Void;
		static function write_string(handle:Int, s:String):Void;
	static function flush_stdin(handle:Int):Void;
	static function kill(handle:Int):Void;
	static function close(handle:Int):Int;
}
