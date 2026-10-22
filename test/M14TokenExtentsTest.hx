/** Token boundaries belong to original source, before trailing trivia or decoding. */
class M14TokenExtentsTest {
	static function main():Void {
		final source = '/*😀*/ var /* gap */ x = "é😀\\n"; // tail\n0x2a_i32 .5e+2 ~/a\\/b/gi null null';
		final spellings = [
			"var",
			"x",
			"=",
			'"é😀\\n"',
			";",
			"0x2a_i32",
			".5e+2",
			"~/a\\/b/gi",
			"null",
			"null"
		];
		// These are Unicode offsets in the written source, independent of host string indexing.
		final starts = [6, 20, 22, 24, 30, 40, 49, 55, 65, 70];
		final ends = [9, 21, 23, 30, 31, 48, 54, 64, 69, 74];
		final lexer = new HxLexer(source);
		final offsets = new HxSourceOffsetCursor(source);
		for (index in 0...spellings.length) {
			final token = lexer.next();
			final end = token.endIndex;
			if (end == null)
				throw "authored token has no end";
			if (source.substring(token.pos.index, end) != spellings[index])
				throw "token extent includes trivia or decoded spelling";
			if (offsets.advance(token.pos.index) != starts[index] || offsets.advance(end) != ends[index])
				throw "token extent lost original Unicode offsets";
			if (index == 3) {
				switch token.kind {
					case TString(value, false) if (value == "é😀\n"):
					case _:
						throw "token extent changed string decoding";
				}
			}
			if (index == 5 && (token.numericText != "0x2a" || token.numericSuffix != "i32"))
				throw "token extent changed numeric spelling or suffix";
		}
		final eof = lexer.next();
		if (!eof.kind.match(TEof) || eof.endIndex != source.length || eof.pos.index != source.length || offsets.advance(eof.pos.index) != 74)
			throw "EOF must have an empty extent at source end";
		final synthetic = new HxToken(TIdent("synthetic"), new HxPos(3, 1, 4));
		if (synthetic.endIndex != null)
			throw "synthetic token invented an end";
		final forkSource = "one /* comment */ two   ";
		final original = new HxLexer(forkSource);
		final first = original.next();
		final fork = original.fork();
		final forkSecond = fork.next();
		final forkEnd = fork.next();
		final originalSecond = original.next();
		if (first.endIndex != 3
			|| forkSecond.pos.index != 18
			|| forkSecond.endIndex != 21
			|| originalSecond.endIndex != 21
			|| forkEnd.endIndex != forkSource.length
			|| original.next().endIndex != forkSource.length)
			throw "lookahead changed an existing token or the original cursor";
		final empty = new HxLexer("").next();
		if (empty.pos.index != 0 || empty.endIndex != 0)
			throw "empty source EOF extent differs";
		Sys.println("TOKEN_EXTENTS:PASS");
	}
}
