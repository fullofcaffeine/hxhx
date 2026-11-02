/**
	Runs the `EReg` API on text with one-, two-, three- and four-byte UTF-8
	characters (`h`, `é`, `漢`, `😀`). Upstream Haxe 4.3.7 eval counts Unicode
	code points, so every position below is a code-point index that agrees
	with `String.substr` and `String.charAt`, and `.` or a character class
	matches one whole character.

	Every line printed here matches upstream `haxe --interp`
	(`haxe -cp src --run Main` prints the first part of `expected.stdout`).
	`PortableMain` runs this class and then adds OCaml-only lines where
	upstream eval is not self-consistent.
**/
class Main {
	static function pos(r:EReg):String {
		final p = r.matchedPos();
		return p.pos + "+" + p.len;
	}

	static function each(r:EReg, s:String):String {
		return r.map(s, m -> "[" + m.matched(0) + "]");
	}

	public static function main():Void {
		final s = "héllo😀漢l";

		final run = ~/l+/;
		run.match(s);
		Sys.println("matchedPos=" + pos(run) + " left=" + run.matchedLeft() + " right=" + run.matchedRight() + " substr="
			+ s.substr(run.matchedPos().pos, run.matchedPos().len) + " charAt=" + s.charAt(run.matchedPos().pos));

		final last = ~/l$/;
		last.match(s);
		Sys.println("after multibyte=" + pos(last) + " " + s.charAt(last.matchedPos().pos) + " left=" + last.matchedLeft());

		final emoji = ~/😀+/;
		emoji.match("漢😀😀x");
		Sys.println("emoji run=" + pos(emoji) + " " + emoji.matched(0) + " right=" + emoji.matchedRight());

		Sys.println("dot=" + each(~/./g, "é漢😀a") + " anchored=" + ~/^...$/.match("é漢😀") + "," + ~/^....$/.match("é漢😀"));
		Sys.println("dot newline=" + each(~/./g, "é\n漢").split("\n").join("\\n") + " dotall=" + each(~/./gs, "é\n漢").split("\n").join("\\n"));
		Sys.println("dot plus=" + each(~/é.+l/g, s) + " star=" + each(~/o.*/g, s));
		final around = ~/^(.*)(漢)([^x]+)$/;
		around.match("é😀漢ab😀");
		Sys.println("star groups=" + around.matched(1) + "|" + around.matched(2) + "|" + around.matched(3) + "|" + pos(around));

		final group = ~/(é)(.)(漢)?/;
		group.match("aé😀b");
		Sys.println("groups=" + group.matched(1) + "|" + group.matched(2) + "|" + group.matched(3) + "|" + pos(group));

		Sys.println("negated=" + each(~/[^a]/g, "aéb漢") + " members=" + each(~/[é漢]+/g, "xé漢éy漢") + " range=" + each(~/[à-ü]/g, "aéxüÿ"));
		Sys.println("negated members=" + each(~/[^é漢a]+/g, "aé😀b漢c") + " negated star=" + each(~/x[^,]*/g, "xé漢,x😀"));
		Sys.println("optional=" + each(~/hé?l/g, "hél hl hé") + " literal plus=" + each(~/漢+/g, "a漢漢b漢"));
		Sys.println("non-capturing=" + each(~/(?:é漢)+(.)/g, "xé漢é漢😀y") + " escaped=" + each(~/\x{e9}|\t/g, "aé\tb"));

		final ci = ~/É+/i;
		ci.match("xéÉé");
		Sys.println("caseless=" + pos(ci) + " " + ci.matched(0) + " cyrillic=" + ~/ж/i.match("Ж") + " greek=" + ~/σ/i.match("Σ") + " range="
			+ each(~/[à-ü]+/gi, "xÀÉy") + " ascii=" + each(~/abc/gi, "éABCabc") + " class=" + each(~/[é]/gi, "eÉé"));
		Sys.println("caseless no full folding="
			+ ~/straße/i.match("STRASSE")
			+ " negated="
			+ each(~/[^é]+/gi, "ÉéxEe")
			+ ","
			+ each(~/[^a]+/gi, "AAbbA"));

		Sys.println("split=" + ~/,/g.split("é,漢,😀").join("/") + " once=" + ~/,/.split("é,漢,😀").join("/") + " spaced="
			+ ~/\s*;\s*/g.split("漢 ; é;😀").join("/"));
		Sys.println("replace=" + ~/(l)/g.replace(s, "[$1]") + " once=" + ~/(漢)/.replace(s, "<$1>") + " multibyte=" + ~/l/g.replace(s, "ł"));
		Sys.println("map positions=" + ~/l/g.map(s, m -> pos(m)) + " map left=" + ~/😀/.map(s, m -> m.matchedLeft().length + ""));

		final ascii = "abc漢d";
		final sub = ~/漢/;
		Sys.println("matchSub ascii prefix=" + sub.matchSub(ascii, 1) + " " + pos(sub) + " bounded=" + ~/c/.matchSub(ascii, 0, 2) + ","
			+ ~/b/.matchSub(ascii, 0, 2));
		final first = ~/l/;
		first.matchSub(s, 0);
		Sys.println("matchSub first=" + pos(first) + " left=" + first.matchedLeft());

		Sys.println("empty ascii map="
			+ ~/x*/g.map("ab", m -> "-")
			+ " replace="
			+ ~/x*/g.replace("ab", "-")
			+ " split="
			+ ~/x*/g.split("ab").join("/"));

		final longText = new StringBuf();
		for (i in 0...50)
			longText.add("é漢😀");
		longText.add("needle");
		final needle = ~/needle/;
		final text = longText.toString();
		needle.match(text);
		Sys.println("long=" + pos(needle) + " " + text.substr(needle.matchedPos().pos) + " dots=" + ~/😀./g.map(text, m -> "").length);

		Sys.println("escape=" + EReg.escape("é.漢+"));
	}
}
