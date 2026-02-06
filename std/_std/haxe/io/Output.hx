package haxe.io;

import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Error;
import haxe.io.Input;

/**
	OCaml target override for `haxe.io.Output`.

	Why
	- The upstream default implementation of `Output.writeBytes` indexes into `BytesData`
	  via `untyped b[pos]`. On our OCaml target, `BytesData` is an **opaque runtime value**
	  (backed by OCaml `bytes`), so that indexing strategy does not typecheck in OCaml.
	- We keep the public Haxe API intact, but re-implement the “default” methods in a way
	  that only uses the stable `Bytes.get`/`Bytes.set` surface, which our backend maps to
	  `HxBytes.*` runtime helpers.

	What
	- `writeByte` remains abstract (subclasses override).
	- `writeBytes` is implemented by looping over `Bytes.get` and calling `writeByte`.
	- Higher-level helpers (`writeFullBytes`, `writeString`, numeric writers) are kept as
	  compatibility scaffolding for early bootstrapping.

	How
	- Correctness-first: this is not the fastest possible implementation, but it is stable.
**/
class Output {
	public var bigEndian(default, set):Bool;

	function set_bigEndian(b:Bool):Bool {
		bigEndian = b;
		return b;
	}

	/** Write one byte. */
	public function writeByte(c:Int):Void {
		// Mark argument used to avoid strict unused-var warnings in OCaml builds.
		if (c == -1) {}
		throw new haxe.exceptions.NotImplementedException();
	}

	/**
		Write `len` bytes from `s` starting at `pos`.

		This default implementation is intentionally simple: it uses `Bytes.get` so it works
		with opaque `BytesData` representations.
	**/
	public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		#if !neko
		if (pos < 0 || len < 0 || pos + len > s.length) throw Error.OutsideBounds;
		#end
		var k = len;
		while (k > 0) {
			writeByte(s.get(pos));
			pos++;
			k--;
		}
		return len;
	}

	/** Flush any buffered data. */
	public function flush():Void {}

	/** Close the output. */
	public function close():Void {}

	/* ------------------ API ------------------ */

	public function write(s:Bytes):Void {
		var l = s.length;
		var p = 0;
		while (l > 0) {
			var k = writeBytes(s, p, l);
			if (k == 0) throw Error.Blocked;
			p += k;
			l -= k;
		}
	}

	public function writeFullBytes(s:Bytes, pos:Int, len:Int):Void {
		while (len > 0) {
			var k = writeBytes(s, pos, len);
			pos += k;
			len -= k;
		}
	}

	public function prepare(_nbytes:Int):Void {}

	public function writeInput(i:Input, ?bufsize:Int):Void {
		// Mark arguments used to avoid strict unused-var warnings in OCaml builds.
		if (i == null) {}
		if (bufsize != null) {}

		// Not implemented yet on the OCaml target.
		//
		// Rationale: this helper requires a fully working `Input` + `Bytes` stack.
		// Stage 0/1/2 bootstrapping does not need it, and Stage 4 uses a line-based
		// transport implemented via `sys.io.Process`.
		//
		// We keep the method so code can typecheck, but throw if called.
		throw new haxe.exceptions.NotImplementedException();
	}

	public function writeString(s:String, ?encoding:Encoding):Void {
		// OCaml target (M6): only default encoding is supported for now.
		// Ignore the encoding parameter to keep the portable API usable.
		if (encoding != null) {}
		var b = Bytes.ofString(s);
		writeFullBytes(b, 0, b.length);
	}

	// Numeric helpers (kept for compatibility; implemented via writeByte).

	public function writeInt8(x:Int):Void {
		if (x < -0x80 || x >= 0x80) throw Error.Overflow;
		writeByte(x & 0xFF);
	}

	public function writeUInt8(x:Int):Void {
		if (x < 0 || x >= 0x100) throw Error.Overflow;
		writeByte(x);
	}

	public function writeInt16(x:Int):Void {
		if (x < -0x8000 || x >= 0x8000) throw Error.Overflow;
		writeUInt16(x & 0xFFFF);
	}

	public function writeUInt16(x:Int):Void {
		if (x < 0 || x >= 0x10000) throw Error.Overflow;
		if (bigEndian) {
			writeByte(x >> 8);
			writeByte(x & 0xFF);
		} else {
			writeByte(x & 0xFF);
			writeByte(x >> 8);
		}
	}

	public function writeInt24(x:Int):Void {
		if (x < -0x800000 || x >= 0x800000) throw Error.Overflow;
		writeUInt24(x & 0xFFFFFF);
	}

	public function writeUInt24(x:Int):Void {
		if (x < 0 || x >= 0x1000000) throw Error.Overflow;
		if (bigEndian) {
			writeByte(x >> 16);
			writeByte((x >> 8) & 0xFF);
			writeByte(x & 0xFF);
		} else {
			writeByte(x & 0xFF);
			writeByte((x >> 8) & 0xFF);
			writeByte(x >> 16);
		}
	}

	public function writeInt32(x:Int):Void {
		if (bigEndian) {
			writeByte(x >>> 24);
			writeByte((x >> 16) & 0xFF);
			writeByte((x >> 8) & 0xFF);
			writeByte(x & 0xFF);
		} else {
			writeByte(x & 0xFF);
			writeByte((x >> 8) & 0xFF);
			writeByte((x >> 16) & 0xFF);
			writeByte(x >>> 24);
		}
	}
}
