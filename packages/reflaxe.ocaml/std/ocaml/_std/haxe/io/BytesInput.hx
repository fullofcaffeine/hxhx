package haxe.io;

/**
	OCaml target override for `haxe.io.BytesInput`.

	Why this exists
	- Upstream `BytesInput` uses direct `BytesData` array indexing (`b[pos]`) for fast paths.
	- In this target, `BytesData` is intentionally opaque, so generic array-index lowering can
	  degrade to non-byte runtime helpers and crash in strict portable runs.

	How this override works
	- Reads are routed through `Bytes.fastGet`, which the backend maps to the
	  native-data `HxBytes.fastGet` primitive.
	- Buffer copies are routed through `buf.set(..., Bytes.fastGet(...))`, avoiding raw
	  `BytesData` indexing while preserving observable behavior.
**/
class BytesInput extends Input {
	var b:BytesData;
	var pos:Int;
	var len:Int;
	var totlen:Int;

	public var position(get, set):Int;
	public var length(get, never):Int;

	public function new(bytes:Bytes, ?position:Int, ?length:Int) {
		if (position == null)
			position = 0;
		if (length == null)
			length = bytes.length - position;
		if (position < 0 || length < 0 || position + length > bytes.length)
			throw Error.OutsideBounds;
		this.b = bytes.getData();
		this.pos = position;
		this.len = length;
		this.totlen = length;
	}

	inline function get_position():Int {
		return pos;
	}

	inline function get_length():Int {
		return totlen;
	}

	function set_position(next:Int):Int {
		var normalized = next;
		if (normalized < 0)
			normalized = 0;
		else if (normalized > length)
			normalized = length;
		len = totlen - normalized;
		pos = normalized;
		return normalized;
	}

	public override function readByte():Int {
		if (len == 0)
			throw new Eof();
		final value = Bytes.fastGet(b, pos);
		pos++;
		len--;
		return value;
	}

	public override function readBytes(buf:Bytes, position:Int, length:Int):Int {
		if (position < 0 || length < 0 || position + length > buf.length)
			throw Error.OutsideBounds;
		if (len == 0 && length > 0)
			throw new Eof();

		var readLength = length;
		if (len < readLength)
			readLength = len;

		final sourceStart = pos;
		for (index in 0...readLength) {
			buf.set(position + index, Bytes.fastGet(b, sourceStart + index));
		}

		pos += readLength;
		len -= readLength;
		return readLength;
	}
}
