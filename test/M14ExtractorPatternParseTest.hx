/**
	In Haxe 4.3.7, any pattern followed by a top-level `=>` is an extractor: the left side is an
	expression over the matched value `_`, and the right side is the pattern for its result.
	Upstream accepts `_ + "," + _ => "abc,abc"`, `_ * 2 => 2`, `_ >= (10) => true`,
	`{year: _ < 1970 => true}`, `(_ : Array<Dynamic>) => []`, and `_ =>` with the result pattern
	on the next line.

	The hxhx parser looked for `=>` only after a qualified name or a lower-case call, such as
	`_.length` or `f(_)`. Other extractors failed with "Expected ':'". Five upstream unit-suite
	modules failed for this reason (haxe_ocaml-rsbh4).
**/
@:access(HxParser)
class M14ExtractorPatternParseTest {
	static function pattern(source:String):{pattern:HxSwitchPattern, next:HxTokenKind} {
		final parser = new HxParser(source);
		final parsed = try parser.parseSwitchPattern() catch (e:haxe.Exception) throw source + ": parse failed: " + e.message;
		return {pattern: parsed, next: parser.cur.kind};
	}

	static function expectExtractor(source:String, text:String, result:HxSwitchPattern):Void {
		final parsed = pattern(source);
		switch parsed.pattern {
			case PExtractor(actualText, actualResult) if (actualText == text && Std.string(actualResult) == Std.string(result)):
			case _:
				throw source + ": expected PExtractor(" + text + ", " + result + "), got " + parsed.pattern;
		}
		if (!parsed.next.match(TColon))
			throw source + ": the pattern must end before ':', next is " + parsed.next;
	}

	static function expectPattern(source:String, expected:HxSwitchPattern):Void {
		final parsed = pattern(source);
		if (Std.string(parsed.pattern) != Std.string(expected))
			throw source + ": expected " + expected + ", got " + parsed.pattern;
	}

	static function main():Void {
		expectExtractor('_ + "," + _ => "abc,abc":', '_ + "," + _', PString("abc,abc"));
		expectExtractor("_ * 2 => 2:", "_ * 2", PInt(2));
		expectExtractor("_ >= (10) => true:", "_ >= (10)", PBool(true));
		expectExtractor("_ =>\n\t[1]:", "_", PArray([PInt(1)]));
		expectExtractor("(_ : Array<Dynamic>) => []:", "(_ : Array<Dynamic>)", PArray([]));

		final object = pattern('{year: _ < 1970 => true, name: "x"}:').pattern;
		switch object {
			case PObject(["year", "name"], [PExtractor("_ < 1970", PBool(true)), PString("x")]):
			case _:
				throw "object field extractor: got " + object;
		}

		// Existing extractor and ordinary forms keep their meaning.
		expectExtractor("_.length => 0:", "_.length", PInt(0));
		expectPattern("_:", PWildcard);
		expectPattern("(1 | 2):", POr([PInt(1), PInt(2)]));
		expectPattern("[_, 3]:", PArray([PWildcard, PInt(3)]));
		final nested = pattern("[f(_) => 1, _]:").pattern;
		switch nested {
			case PArray([PExtractor("f(_)", PInt(1)), PWildcard]):
			case _:
				throw "nested extractor: got " + nested;
		}

		Sys.println("M14_EXTRACTOR_PATTERN_PARSE:PASS");
	}
}
