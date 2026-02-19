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

	public function addInt32(v:Int):Void {
		addByte(v & 0xFF);
		addByte((v >> 8) & 0xFF);
		addByte((v >> 16) & 0xFF);
		addByte(v >>> 24);
	}

	public function addInt64(v:haxe.Int64):Void {
		// Ensure the OCaml build sees the `Haxe_Int64` module as an explicit dependency.
		//
		// Why this exists:
		// - `haxe.Int64` inlines to direct `high/low` field access on its underlying record.
		// - Our generated OCaml for `v.low`/`v.high` uses record field labels. Those labels are
		//   only known to `ocamlc` if the defining module has been loaded (via a module reference).
		// - Without a direct reference, dune can compile this module before `Haxe_Int64`, causing
		//   an "Unbound record field low/high" error during bring-up.
		//
		// This extern call forces a non-inlined module reference so dune orders compilation correctly.
		_HxInt64Dep.touch(0, 0);
		addInt32(v.low);
		addInt32(v.high);
	}

	public function addFloat(v:Float):Void {
		addInt32(FPHelper.floatToI32(v));
	}

	public function addDouble(v:Float):Void {
		addInt64(FPHelper.doubleToI64(v));
	}

	public function addBytes(src:Bytes, pos:Int, len:Int):Void {
		if (pos < 0 || len < 0 || pos + len > src.length)
			throw Error.OutsideBounds;
		for (i in pos...pos + len) {
			b.push(src.get(i));
		}
	}

	public function getBytes():Bytes {
		final out = Bytes.alloc(b.length);
		for (i in 0...b.length)
			out.set(i, b[i]);
		return out;
	}
}

/**
	Internal native dependency marker for OCaml builds.

	See `BytesBuffer.addInt64` for why this exists.
**/
@:native("Haxe_Int64")
private extern class _HxInt64Dep {
	@:native("___int64_create") public static function touch(high:Int, low:Int):Dynamic;
}
