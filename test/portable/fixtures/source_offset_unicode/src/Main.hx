/** Verify the compiler's source-offset conversion through the actual OCaml runtime. */
class Main {
	static function main():Void {
		final parts = ["a", "é", "☕", "🙂", "z"];
		final source = parts.join("");
		final cursor = new HxSourceOffsetCursor(source);
		if (cursor.advance(0) != 0)
			throw "source cursor did not start at zero";
		var rawOffset = 0;
		for (index in 0...parts.length) {
			rawOffset += parts[index].length;
			if (cursor.advance(rawOffset) != index + 1 || cursor.advance(rawOffset) != index + 1)
				throw "source cursor confused string units with Unicode offsets";
		}
		var rejected = false;
		try
			cursor.advance(0)
		catch (_:haxe.Exception)
			rejected = true;
		if (!rejected)
			throw "source cursor accepted a rewind";
		rejected = false;
		try
			cursor.advance(source.length + 1)
		catch (_:haxe.Exception)
			rejected = true;
		if (!rejected)
			throw "source cursor accepted a boundary outside the source";
		Sys.println("source-offsets:5");
	}
}
