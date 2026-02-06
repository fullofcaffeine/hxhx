package haxe.io;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Eof;
import haxe.io.Error;

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
			total.add(buf.sub(0, len));
		}
		return total.getBytes();
	}

	public function readFullBytes(s:Bytes, pos:Int, len:Int):Void {
		while (len > 0) {
			final k = readBytes(s, pos, len);
			if (k == 0) throw new Eof();
			pos += k;
			len -= k;
		}
	}

	public function readLine():String {
		final out = new StringBuf();
		while (true) {
			final c = readByte();
			if (c == "\n".code) break;
			if (c == "\r".code) {
				// Handle CRLF: if next is LF, consume it.
				try {
					final n = readByte();
					if (n != "\n".code) {
						// Best-effort: put it back is not supported; keep it.
						out.addChar(n);
					}
				} catch (_:Eof) {}
				break;
			}
			out.addChar(c);
		}
		return out.toString();
	}
}
