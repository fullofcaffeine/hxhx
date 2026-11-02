/**
	Find where an `import` or `using` directive names its path in module source.

	Parsed directives keep only their path, so a diagnostic about one locates
	the path text after the `import`/`using` keyword. The search skips line and
	block comments. When the text cannot be found, the position is unknown.
**/
class TyDirectivePosition {
	public static function find(source:Null<String>, path:String):HxPos {
		if (source == null)
			return HxPos.unknown();
		final pattern = new EReg("\\b(import|using)\\s+(" + StringTools.replace(path, ".", "\\s*\\.\\s*") + ")\\b", "");
		var offset = 0;
		final masked = mask(source);
		while (pattern.matchSub(masked, offset)) {
			final at = pattern.matchedPos();
			final start = at.pos + masked.substr(at.pos, at.len).indexOf(pattern.matched(2));
			return position(source, start);
		}
		return HxPos.unknown();
	}

	/** Replace comment text with spaces so the offsets stay the same. */
	static function mask(source:String):String {
		final out = new StringBuf();
		var index = 0;
		while (index < source.length) {
			if (StringTools.startsWith(source.substr(index, 2), "//")) {
				while (index < source.length && source.charAt(index) != "\n") {
					out.add(" ");
					index++;
				}
			} else if (StringTools.startsWith(source.substr(index, 2), "/*")) {
				while (index < source.length && !StringTools.startsWith(source.substr(index, 2), "*/")) {
					out.add(source.charAt(index) == "\n" ? "\n" : " ");
					index++;
				}
				if (index < source.length) {
					out.add("  ");
					index += 2;
				}
			} else {
				out.add(source.charAt(index));
				index++;
			}
		}
		return out.toString();
	}

	static function position(source:String, index:Int):HxPos {
		var line = 1;
		var column = 1;
		for (offset in 0...index) {
			if (source.charCodeAt(offset) == "\n".code) {
				line++;
				column = 1;
			} else {
				column++;
			}
		}
		return new HxPos(index, line, column);
	}
}
