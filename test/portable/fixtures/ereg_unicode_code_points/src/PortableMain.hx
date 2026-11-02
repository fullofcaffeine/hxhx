/**
	Runs the upstream-parity checks in `Main`, then OCaml-only lines.

	The `#if !eval` lines have no faithful upstream value:

	- Upstream eval reads the `matchSub` position as a UTF-8 byte offset while
	  `matchedPos` returns code points, so a loop that feeds `matchedPos` back
	  into `matchSub` repeats one match forever once multibyte text comes first.
	  The OCaml runtime reads `matchSub` positions and lengths as code points,
	  like every other `EReg` and `String` position.
	- Upstream eval steps over an empty global match one byte at a time. On
	  non-ASCII text, `split` and `replace` then cut characters in half and
	  `map` stops with a PCRE error. The OCaml runtime steps one character.
	- Syntax the runtime cannot translate raises when the `EReg` is created;
	  upstream supports most of it.
	- `\W` is the ASCII complement here, while upstream uses Unicode word
	  characters, and an out-of-range `matchSub` returns false where upstream
	  stops the program.
**/
class PortableMain {
	static function rejected(pattern:String):String {
		return try {
			new EReg(pattern, "");
			"created";
		} catch (e:Dynamic)
			"rejected";
	}

	static function main():Void {
		Main.main();
		#if !eval
		final s = "héllo😀漢l";
		final r = ~/l/;
		final found = [];
		var at = 0;
		while (found.length < 10 && r.matchSub(s, at)) {
			final p = r.matchedPos();
			found.push(p.pos + ":" + s.charAt(p.pos));
			at = p.pos + p.len;
		}
		Sys.println("matchSub loop=" + found.join(","));
		final bounded = ~/漢/;
		Sys.println("matchSub code points=" + bounded.matchSub(s, 6, 1) + "," + ~/漢/.matchSub(s, 0, 6) + "," + ~/l/.matchSub(s, 4) + " "
			+ ~/a+/.matchSub("éaaa", 1, 2) + " len=" + bounded.matchedPos().len);
		Sys.println("unsupported=" + rejected("a(?=b)") + "," + rejected("\\Aab\\z") + "," + rejected("a\\Bb") + "," + rejected("\\q") + ","
			+ rejected("(ab){2}") + "," + rejected("[é][é][é][é][é][é][é][é][é](a)\\1") + " nul=" + new EReg("a\\0b", "").match("a\x00b"));
		Sys.println("ascii word classes=" + ~/\W/g.map("aé-", m -> "[" + m.matched(0) + "]") + " matchSub past end=" + ~/x/.matchSub("ab", 3) + ","
			+ ~/x/.matchSub("ab", -1) + "," + ~/b/.matchSub("ab", 1, 2));
		Sys.println("empty unicode map=" + ~/x*/g.map("é漢", m -> "-") + " replace=" + ~/x*/g.replace("é漢😀", "-") + " split=" + ~/x*/g.split("é漢😀")
			.join("/"));
		#end
	}
}
