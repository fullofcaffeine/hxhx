package haxe.io;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Eof;
import haxe.io.Error;
import haxe.io.FPHelper;

/**
	OCaml target override for `haxe.io.Input`.

	Why
	- The upstream default `Input.readBytes` implementation writes into `BytesData` using
	  `b[pos] = ...`. On our OCaml target, `BytesData` is an opaque runtime value and
	  cannot be indexed that way in generated OCaml.
	- We provide a compatibility implementation that only uses `Bytes.set`/`Bytes.get`,
	  which the backend maps to `HxBytes.*` runtime helpers.

	What
	- `readByte` remains abstract (subclasses override).
	- `readBytes` is implemented by repeatedly calling `readByte` and `Bytes.set`.
	- Higher-level helpers (`readAll`, `readFullBytes`, `readLine`) are implemented in
	  terms of those primitives.

	How
	- Correctness-first: this is not optimized, but it is stable and deterministic.
**/
class Input {
	public var bigEndian(default, set):Bool;

	function set_bigEndian(b:Bool):Bool {
		bigEndian = b;
		return b;
	}

	/** Read and return one byte. */
	public function readByte():Int {
		return throw new haxe.exceptions.NotImplementedException();
	}

	/**
		Read up to `len` bytes into `s` starting at `pos`.

		Returns the number of bytes actually read, which may be smaller than `len`
		if EOF is reached.
	**/
	public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (pos < 0 || len < 0 || pos + len > s.length) throw Error.OutsideBounds;
		var k = len;
		try {
			while (k > 0) {
				s.set(pos, readByte());
				pos++;
				k--;
			}
		} catch (_:Eof) {}
		return len - k;
	}

	/** Close the input source. */
	public function close():Void {}

	/* ------------------ API ------------------ */

	public function readAll(?bufsize:Int):Bytes {
		final size:Int = bufsize == null ? (1 << 14) : (cast bufsize);
		final buf = Bytes.alloc(size);
		final total = new BytesBuffer();
		while (true) {
			final len = readBytes(buf, 0, size);
			if (len == 0) break;
			total.addBytes(buf, 0, len);
		}
		return total.getBytes();
	}

	public function readFullBytes(s:Bytes, pos:Int, len:Int):Void {
		while (len > 0) {
			final k = readBytes(s, pos, len);
			if (k == 0) throw Error.Blocked;
			pos += k;
			len -= k;
		}
	}

	public function read(nbytes:Int):Bytes {
		final s = Bytes.alloc(nbytes);
		var p = 0;
		while (nbytes > 0) {
			final k = readBytes(s, p, nbytes);
			if (k == 0) throw Error.Blocked;
			p += k;
			nbytes -= k;
		}
		return s;
	}

	public function readUntil(end:Int):String {
		final buf = new BytesBuffer();
		var last:Int;
		while ((last = readByte()) != end) {
			buf.addByte(last);
		}
		return buf.getBytes().toString();
	}

	public function readLine():String {
		final buf = new BytesBuffer();
		var last:Int;
		var s:String;
		try {
			while ((last = readByte()) != "\n".code) {
				buf.addByte(last);
			}
			s = buf.getBytes().toString();
			if (s.length > 0 && s.charCodeAt(s.length - 1) == "\r".code) {
				s = s.substr(0, -1);
			}
		} catch (e:Eof) {
			s = buf.getBytes().toString();
			if (s.length == 0) throw e;
		}
		return s;
	}

	public function readFloat():Float {
		return FPHelper.i32ToFloat(readInt32());
	}

	public function readDouble():Float {
		final i1 = readInt32();
		final i2 = readInt32();
		return bigEndian ? FPHelper.i64ToDouble(i2, i1) : FPHelper.i64ToDouble(i1, i2);
	}

	public function readInt8():Int {
		final n = readByte();
		return n >= 128 ? (n - 256) : n;
	}

	public function readInt16():Int {
		final ch1 = readByte();
		final ch2 = readByte();
		final n = bigEndian ? (ch2 | (ch1 << 8)) : (ch1 | (ch2 << 8));
		return (n & 0x8000) != 0 ? (n - 0x10000) : n;
	}

	public function readUInt16():Int {
		final ch1 = readByte();
		final ch2 = readByte();
		return bigEndian ? (ch2 | (ch1 << 8)) : (ch1 | (ch2 << 8));
	}

	public function readInt24():Int {
		final ch1 = readByte();
		final ch2 = readByte();
		final ch3 = readByte();
		final n = bigEndian ? (ch3 | (ch2 << 8) | (ch1 << 16)) : (ch1 | (ch2 << 8) | (ch3 << 16));
		return (n & 0x800000) != 0 ? (n - 0x1000000) : n;
	}

	public function readUInt24():Int {
		final ch1 = readByte();
		final ch2 = readByte();
		final ch3 = readByte();
		return bigEndian ? (ch3 | (ch2 << 8) | (ch1 << 16)) : (ch1 | (ch2 << 8) | (ch3 << 16));
	}

	public function readInt32():Int {
		final ch1 = readByte();
		final ch2 = readByte();
		final ch3 = readByte();
		final ch4 = readByte();
		return bigEndian
			? (ch4 | (ch3 << 8) | (ch2 << 16) | (ch1 << 24))
			: (ch1 | (ch2 << 8) | (ch3 << 16) | (ch4 << 24));
	}

	public function readString(len:Int, ?encoding:Encoding):String {
		// OCaml target (M6): only default encoding is supported for now.
		// Ignore the encoding parameter to keep the portable API usable.
		if (encoding != null) {}
		final b = Bytes.alloc(len);
		readFullBytes(b, 0, len);
		return b.getString(0, len);
	}
}
