package backend.cpp;

/** Emit exact UTF-8 bytes, including embedded zeroes, without depending on C++ source encoding. */
function literal(value:String):String {
	return "std::string(" + quotedBytes(value) + ", " + haxe.io.Bytes.ofString(value).length + ")";
}

/** Static metadata uses a C++ byte literal with static lifetime, not an owned temporary string. */
function quotedBytes(value:String):String {
	final bytes = haxe.io.Bytes.ofString(value);
	final out = new StringBuf();
	out.add('"');
	for (index in 0...bytes.length) {
		final byte = bytes.get(index);
		out.add("\\" + (byte >> 6) + ((byte >> 3) & 7) + (byte & 7));
	}
	out.add('"');
	return out.toString();
}
