/**
	`HxSourceRange` offsets and `HxLineTable` text match upstream Haxe 4.3.7 positions.

	Fixture: `test/fixtures/macro_source_positions`. Its `.hx` files are upstream probes, kept
	byte for byte (its `hxformat.json` turns formatting off, and `.gitattributes` keeps their
	CRLF and CR line ends). `upstream.txt` is what upstream printed for them; see the fixture
	README. Each macro argument line there, `ARG <expr> min=<a> max=<b> #pos(<text>)`, must give
	the same text from `HxLineTable.describe`.

	Named cases (haxe_ocaml-9sj5p.2, positions PR 1):
	- a non-BMP prefix: `base` at 59-63 is `A.hx:3: characters 23-27`;
	- CRLF line ends: `base` at 47-51 is on line 3, `characters 9-13`;
	- lone CR line ends: `base` at 45-49 is on line 3;
	- an escaped string `"e\n\"x"` is 8 code points wide (102-110);
	- a file that cannot be read reports line 1 (`Nope.hx:1: characters 6-3`).
**/
class M14MacroSourcePositionsTest {
	static final root = "test/fixtures/macro_source_positions";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function equal(actual:String, expected:String, label:String):Void
		require(actual == expected, label + ": expected `" + expected + "`, got `" + actual + "`");

	static function text(file:String):String
		return sys.io.File.getContent(root + "/" + file);

	static function table(file:String):HxLineTable
		return HxLineTable.forFile(root + "/" + file);

	/** The written source between two code-point offsets. */
	static function written(file:String, min:Int, max:Int):String
		return text(file).substr(min, max - min);

	static function main():Void {
		final upstream = text("upstream.txt");

		// The named cases.
		final base = new HxSourceRange("A.hx", 59, 63);
		equal(table("A.hx").describe(base), "A.hx:3: characters 23-27", "non-BMP prefix");
		equal(written("A.hx", 59, 63), "base", "non-BMP prefix offsets count code points");
		final crlf = new HxSourceRange("B.hx", 47, 51);
		require(table("B.hx").line(47) == 3, "CRLF: offset 47 is not on line 3");
		equal(table("B.hx").describe(crlf), "B.hx:3: characters 9-13", "CRLF");
		equal(written("B.hx", 47, 51), "base", "CRLF offsets");
		final lone = new HxSourceRange("C.hx", 45, 49);
		require(table("C.hx").line(45) == 3, "lone CR: offset 45 is not on line 3 (a lone CR is a line break)");
		equal(table("C.hx").describe(lone), "C.hx:3: characters 9-13", "lone CR");
		equal(written("C.hx", 45, 49), "base", "lone CR offsets");
		final escaped = new HxSourceRange("A.hx", 102, 110);
		require(escaped.max - escaped.min == 8, "escaped string width");
		equal(written("A.hx", 102, 110), '"e\\n\\"x"', "escaped string covers its written text");
		equal(table("A.hx").describe(escaped), "A.hx:5: characters 9-17", "escaped string");
		final unreadable = HxLineTable.forFile(root + "/Nope.hx");
		require(unreadable.line(5) == 1, "an unreadable file is not one line");
		equal(unreadable.describe(new HxSourceRange("Nope.hx", 5, 2)), "Nope.hx:1: characters 6-3", "unreadable file");

		// Every macro argument upstream printed, with the position text it gave.
		final argument = ~/ARG [\s\S]*? min=([0-9]+) max=([0-9]+) #pos\(([^)]+)\)/;
		var rest = upstream;
		var checked = 0;
		while (argument.match(rest)) {
			final expected = argument.matched(3);
			final file = expected.substr(0, expected.indexOf(":"));
			final range = new HxSourceRange(file, Std.parseInt(argument.matched(1)), Std.parseInt(argument.matched(2)));
			equal(table(file).describe(range), expected, "upstream argument " + range);
			checked++;
			rest = argument.matchedRight();
		}
		require(checked == 14, "expected 14 upstream argument positions in upstream.txt, found " + checked);

		// Positions a macro built (`Context.makePosition` in M.hx and Z.hx): kept as given, and
		// printed as upstream printed them in upstream.txt.
		for (entry in [
			{range: new HxSourceRange("Nope.hx", 5, 2), table: unreadable, expected: "Nope.hx:1: characters 6-3"},
			{range: new HxSourceRange("", 0, 3), table: HxLineTable.forFile(""), expected: ":1: characters 1-4"},
			{range: new HxSourceRange("A.hx", -5, 3), table: table("A.hx"), expected: "A.hx:1: characters -4-4"},
			{range: new HxSourceRange("M.hx", 2, 9), table: table("M.hx"), expected: "M.hx:1: characters 3-10"},
			{range: new HxSourceRange("Nope.hx", 5, 5), table: unreadable, expected: "Nope.hx:1: character 6"},
			{range: new HxSourceRange("A.hx", -1, -1), table: table("A.hx"), expected: "(unknown)"},
			{range: new HxSourceRange("A.hx", 30, 60), table: table("A.hx"), expected: "A.hx:2: lines 2-3"}
		]) {
			require(upstream.indexOf(entry.expected + " : ") >= 0, "upstream.txt does not record `" + entry.expected + "`");
			equal(entry.table.describe(entry.range), entry.expected, "made position " + entry.range);
		}

		// The range keeps what it was given; only min == -1 is unknown.
		final made = new HxSourceRange("Nope.hx", 5, 2);
		require(made.getFile() == "Nope.hx" && made.getMin() == 5 && made.getMax() == 2 && !made.isUnknown(), "a made range changed its values");
		require(HxSourceRange.unknown().isUnknown() && HxSourceRange.unknown().getFile() == "?", "unknown range");
		require(made.equals(new HxSourceRange("Nope.hx", 5, 2)) && !made.equals(new HxSourceRange("Nope.hx", 5, 3)), "range equality");

		Sys.println("M14_MACRO_SOURCE_POSITIONS:PASS");
	}
}
