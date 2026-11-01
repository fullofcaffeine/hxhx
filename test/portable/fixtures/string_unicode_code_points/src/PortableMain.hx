using StringTools;

/**
	Runs the shared Unicode String checks, then the parts Stage3 cannot run yet:
	String iteration, key-value iteration, and `StringTools.replace`.

	The last line is OCaml-only. Upstream eval refuses to make a String from
	ill-formed UTF-8 ("Invalid string"), so there is no upstream value. The
	OCaml runtime counts each ill-formed byte as one character whose code is
	the byte value, and case conversion leaves it unchanged.
**/
class PortableMain {
	static function main():Void {
		Main.main();
		final s = "héllo😀漢";
		final iterated = [];
		for (c in s)
			iterated.push(Std.string(c));
		Sys.println("iterator=" + iterated.join(","));
		final keyed = [];
		for (k => c in s)
			keyed.push(k + ":" + c);
		Sys.println("keyValueIterator=" + keyed.join(","));
		Sys.println("replace=" + StringTools.replace(s, "l", "L") + "|" + s.replace("😀", "-"));
		#if !eval
		// 0x41 'A', a lone 0xFF, a truncated 0xC3, then 'b'.
		final bytes = haxe.io.Bytes.ofHex("41ffc362");
		final invalid = bytes.toString();
		final upper = haxe.io.Bytes.ofString(invalid.toUpperCase()).toHex();
		Sys.println("invalid length=" + invalid.length + " codes=" + invalid.charCodeAt(1) + "," + invalid.charCodeAt(2) + "," + invalid.charCodeAt(3)
			+ " upper=" + upper + " indexOf=" + invalid.indexOf("b"));
		#end
	}
}
