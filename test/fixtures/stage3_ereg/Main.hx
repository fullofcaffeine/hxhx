/**
	Regular expressions on the Stage3 native route.

	Covers regex literals with and without the `g`, `i`, and `m` flags,
	`new EReg(pattern, flags)`, and the instance methods `match`, `matched`,
	`matchedLeft`, `matchedRight`, `matchedPos`, `matchSub`, `replace`, `split`, and `map`,
	plus the static `EReg.escape`.
	The regexes live in locals, a static field, an instance field, and a
	function parameter. Each `match` runs in its own statement before `matched`
	reads the result, so the output does not depend on the evaluation order
	of String concatenation operands (Bead haxe_ocaml-b544p). Only patterns that behave the same in the OCaml `Str`
	translation and in upstream Haxe are used here.
**/
class Holder {
	public var range:EReg;

	public function new() {
		range = ~/([0-9]+)-([0-9]+)/;
	}
}

class Main {
	static var word = ~/[a-z]+/i;
	static var digits = new EReg("[0-9]+", "g");

	static function firstMatch(r:EReg, s:String):String {
		return r.match(s) ? r.matched(0) : "none";
	}

	static function main():Void {
		final found = word.match("123 Hello world");
		Sys.println("static literal i: " + Std.string(found) + " " + word.matched(0));
		Sys.println("static new g: " + digits.replace("a1b22c333", "#"));

		final local = ~/b+/;
		if (local.match("abbbc")) {
			final pos = local.matchedPos();
			Sys.println("local: " + local.matched(0) + " at " + pos.pos + "+" + pos.len);
			Sys.println("sides: " + local.matchedLeft() + "|" + local.matchedRight());
		}
		Sys.println("no match: " + Std.string(local.match("xyz")));

		Sys.println("replace first: " + ~/o/.replace("foo boo", "0"));
		Sys.println("replace all: " + ~/o/g.replace("foo boo", "0"));
		Sys.println("replace groups: " + ~/([a-z]+) ([a-z]+)/.replace("hello world", "$2 $1"));
		Sys.println("split: " + ~/, */g.split("a, b,c,  d").join("|"));
		Sys.println("multiline: " + Std.string(~/^b/m.match("a\nb")));
		Sys.println("case fold: " + Std.string(~/HELLO/i.match("say hello")) + " " + Std.string(~/HELLO/.match("say hello")));

		final sub = ~/[0-9]+/;
		if (sub.matchSub("12 345 6", 2)) {
			final pos = sub.matchedPos();
			Sys.println("matchSub rest: " + sub.matched(0) + " at " + pos.pos + "+" + pos.len);
		}
		if (sub.matchSub("12 345 6", 2, 4)) {
			final pos = sub.matchedPos();
			Sys.println("matchSub len: " + sub.matched(0) + " at " + pos.pos + "+" + pos.len);
		}
		Sys.println("escape: " + EReg.escape("a.b*c"));

		final constructed = new EReg("([0-9]+)", "g");
		Sys.println("map: " + constructed.map("a1b22c333", r -> "<" + r.matched(1) + ">"));
		final folded = new EReg("abc", "i");
		final foldedFound = folded.match("xxABCxx");
		Sys.println("new i: " + Std.string(foldedFound) + " " + folded.matched(0));

		final holder = new Holder();
		if (holder.range.match("x 12-34 y"))
			Sys.println("field: " + holder.range.matched(1) + "," + holder.range.matched(2));
		holder.range = ~/z+/;
		final reassignedFound = holder.range.match("azzz");
		Sys.println("field reassigned: " + Std.string(reassignedFound) + " " + holder.range.matched(0));

		Sys.println("param literal: " + firstMatch(~/w[a-z]+/, "hello world"));
		Sys.println("param new: " + firstMatch(new EReg("Z", "i"), "abc") + " " + firstMatch(new EReg("Z", "i"), "xyz"));
		Sys.println("param static: " + firstMatch(word, "42 Answer"));
	}
}
