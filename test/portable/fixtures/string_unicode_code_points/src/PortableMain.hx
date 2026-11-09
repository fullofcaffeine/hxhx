using StringTools;

/**
	Runs the shared Unicode String checks, then the parts Stage3 cannot run yet:
	String iteration, key-value iteration, `StringTools.replace`, and the
	positions `EReg` reports on non-ASCII text.

	The last four lines are OCaml-only. Three show `EReg.matchSub` counting code
	points so it agrees with `matchedPos` and `String`; upstream eval reads the
	same `pos` and `len` as byte counts, so a `matchedPos` scan loop never ends
	there (haxe_ocaml-4aoh2). The fourth covers ill-formed UTF-8: upstream eval
	refuses to make such a String ("Invalid string"), so there is no upstream
	value. The OCaml runtime counts each ill-formed byte as one character whose
	code is the byte value, and case conversion leaves it unchanged.
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
		eregPositions();
		#if !eval
		eregMatchSubCodePoints();
		// 0x41 'A', a lone 0xFF, a truncated 0xC3, then 'b'.
		final bytes = haxe.io.Bytes.ofHex("41ffc362");
		final invalid = bytes.toString();
		final upper = haxe.io.Bytes.ofString(invalid.toUpperCase()).toHex();
		Sys.println("invalid length=" + invalid.length + " codes=" + invalid.charCodeAt(1) + "," + invalid.charCodeAt(2) + "," + invalid.charCodeAt(3)
			+ " upper=" + upper + " indexOf=" + invalid.indexOf("b"));
		#end
	}

	/**
		Prints what a match reports on text with multi-byte characters.

		A position must be usable with `String`: `text.substr(matchedPos().pos)`
		has to start at the matched character. `.` is printed by position only,
		because the runtime still matches one byte of `é` (haxe_ocaml-1w6os).
	**/
	static function eregPositions():Void {
		function describe(label:String, r:EReg, text:String):Void {
			final p = r.matchedPos();
			Sys.println(label + "=" + p.pos + ":" + p.len + " substr=[" + text.substr(p.pos, p.len) + "] rest=[" + text.substr(p.pos) + "] left=["
				+ r.matchedLeft() + "] right=[" + r.matchedRight() + "]");
		}
		final twoByte = ~/b/;
		twoByte.match("éb");
		describe("ereg-two-byte", twoByte, "éb");
		final mixed = ~/l+/;
		mixed.match("héllo😀漢l");
		describe("ereg-mixed", mixed, "héllo😀漢l");
		final wide = ~/x/;
		wide.match("漢😀xé");
		describe("ereg-wide", wide, "漢😀xé");
		final literal = ~/é/;
		literal.match("aéb");
		describe("ereg-literal", literal, "aéb");
		final any = ~/./;
		any.match("éb");
		final anyPos = any.matchedPos();
		Sys.println("ereg-any=" + anyPos.pos + ":" + anyPos.len);
		final fromStart = ~/b/;
		fromStart.matchSub("ébéb", 0);
		describe("ereg-sub-start", fromStart, "ébéb");
		final asciiPrefix = ~/b/;
		asciiPrefix.matchSub("abéb", 2);
		describe("ereg-sub-ascii-prefix", asciiPrefix, "abéb");
		Sys.println("ereg-split=" + ~/,/g.split("é,漢,😀").join("|") + " once=" + ~/b/.split("ébéb").join("|"));
		Sys.println("ereg-map=" + ~/b/g.map("ébéb", e -> {
			final p = e.matchedPos();
			"<" + p.pos + ":" + p.len + ">";
		}));
	}

	#if !eval
	/**
		Prints `matchSub` results where `pos` and `len` count code points.

		The loop is the usual way to find every match, and it needs `matchSub` to
		read the position `matchedPos` reported. The attempt limit keeps a
		regression from hanging the test run.
	**/
	static function eregMatchSubCodePoints():Void {
		final after = ~/b/;
		after.matchSub("ébéb", 2);
		final afterPos = after.matchedPos();
		Sys.println("ereg-sub-after=" + afterPos.pos + ":" + afterPos.len + " left=[" + after.matchedLeft() + "]");
		Sys.println("ereg-sub-window=" + ~/b/.matchSub("ébéb", 2, 1) + "," + ~/b/.matchSub("ébéb", 3, 1));
		final scan = ~/b/;
		final found = [];
		var from = 0;
		while (found.length < 6 && scan.matchSub("ébéb", from)) {
			final p = scan.matchedPos();
			found.push(p.pos + ":" + p.len);
			from = p.pos + p.len;
		}
		Sys.println("ereg-sub-scan=" + found.join(","));
	}
	#end
}
