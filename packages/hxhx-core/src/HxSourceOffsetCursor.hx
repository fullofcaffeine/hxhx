/**
	Convert increasing lexer string indices to upstream Haxe source offsets.

	A host string index can count bytes, UTF-16 units or Unicode characters.
	Encoding each consumed segment through Bytes gives the same UTF-8 bytes.
	Counting its leading bytes counts Unicode code points on all those hosts.
	The caller supplies complete token boundaries in already lexed source.

	One parser owns one cursor. Each source segment is counted once, so modules
	with many declarations do not repeatedly scan their entire source prefix.
	This does not change the lexer's internal cursor or diagnostic line policy.
**/
class HxSourceOffsetCursor {
	final source:String;
	var stringOffset:Int = 0;
	var unicodeOffset:Int = 0;

	public function new(source:String) {
		if (source == null)
			throw "source offset cursor requires source text";
		this.source = source;
	}

	/** Return the Unicode offset at the next boundary, rejecting rewinds and missing source. */
	public function advance(index:Int):Int {
		if (index < stringOffset || index > source.length)
			throw "source offset cursor requires increasing boundaries within its source";
		final bytes = haxe.io.Bytes.ofString(source.substring(stringOffset, index));
		for (offset in 0...bytes.length)
			if ((bytes.get(offset) & 0xC0) != 0x80)
				unicodeOffset++;
		stringOffset = index;
		return unicodeOffset;
	}
}
