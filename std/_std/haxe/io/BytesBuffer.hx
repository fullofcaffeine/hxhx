package haxe.io;

/**
	OCaml target override for `haxe.io.BytesBuffer`.

	Why
	- The upstream “generic” `BytesBuffer` fallback uses `Array<Int>` as the backing store.
	  That implementation assumes that `Bytes.ofData(Array<Int>)` is valid, which is not
	  true for this OCaml target: our `BytesData` is an opaque runtime value and
	  `Bytes.ofData` maps to `HxBytes.ofData` expecting an OCaml `bytes` buffer.
	- We provide a target-specific `BytesBuffer` so core helpers like `Input.readAll()`
	  can compile and behave deterministically.

	What
	- A simple `Array<Int>` accumulator (0–255).
	- `getBytes()` materializes a real `Bytes` by allocating and setting each byte.

	How
	- This is intentionally not optimized yet. It exists as a correctness-first bridge
	  while the OCaml runtime surface grows.
**/
class BytesBuffer {
	final b:Array<Int>;

	/** The length of the buffer in bytes. **/
	public var length(get, never):Int;

	public function new() {
		b = [];
	}

	inline function get_length():Int {
		return b.length;
	}

	public inline function addByte(byte:Int):Void {
		b.push(byte);
	}

	public inline function add(src:Bytes):Void {
		for (i in 0...src.length) {
			b.push(src.get(i));
		}
	}

	public inline function addString(v:String, ?encoding:Encoding):Void {
		// OCaml target (M6): only default encoding is supported for now.
		// Ignore the encoding parameter to keep the portable API usable.
		if (encoding != null) {}
		add(Bytes.ofString(v));
	}

	public function getBytes():Bytes {
		final out = Bytes.alloc(b.length);
		for (i in 0...b.length) out.set(i, b[i]);
		return out;
	}
}
