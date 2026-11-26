/**
	A block conditional that follows code on its line (`{#if target.unicode` then lines, then
	`#end`) is selected as upstream Haxe 4.3.7's token-based lexer selects it (haxe_ocaml-w1zmu).

	Upstream's test builder parses each `.unit.hx` file as `"{" + file + "\n}"`, so a file that
	starts with `#if` puts its opener right after `{`. The filter saw a directive only at the start
	of a line, and its inline pass skipped an opener with nothing after it on the line, so the `#if`
	stayed in the text while its `#end` was blanked. The filter must keep every offset (positions
	plan, D6) and leave directives at the start of a line to the block pass.
**/
class M14ConditionalMidLineBlockTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function check(label:String, source:String, defines:haxe.ds.StringMap<String>, kept:Array<String>, dropped:Array<String>):Void {
		final filtered = HxConditionalCompilation.filterSource(source, defines);
		require(filtered.length == source.length, label + ": the filter changed the text length");
		require(filtered.split("\n").length == source.split("\n").length, label + ": the filter changed the line count");
		require(filtered.indexOf("#") < 0, label + ": a directive is left: " + StringTools.replace(filtered, "\n", "|"));
		for (text in kept)
			require(filtered.indexOf(text) >= 0, label + ": `" + text + "` must stay: " + StringTools.replace(filtered, "\n", "|"));
		for (text in dropped)
			require(filtered.indexOf(text) < 0, label + ": `" + text + "` must go: " + StringTools.replace(filtered, "\n", "|"));
		HxParser.parseExprText(filtered);
	}

	static function main():Void {
		final unicode = new haxe.ds.StringMap<String>();
		unicode.set("target.unicode", "1");

		check("defined opener after code", "{#if target.unicode\nvar s = 1;\ns;\n#end\n}", unicode, ["var s = 1;", "s;"], []);
		check("undefined opener after code", "{#if missing\nvar s = 1;\n#end\n}", unicode, [], ["var s"]);
		check("else after a mid-line opener", "{#if missing\nfirst;\n#else\nsecond;\n#end\n}", unicode, ["second;"], ["first;"]);
		check("nested line-start block", "{#if target.unicode\n#if missing\nfirst;\n#else\nsecond;\n#end\n#end\n}", unicode, ["second;"], ["first;"]);
		// The block pass keeps owning a directive at the start of a line.
		check("line-start opener", "{\n#if target.unicode\nvar s = 1;\ns;\n#end\n}", unicode, ["var s = 1;"], []);

		Sys.println("M14_CONDITIONAL_MID_LINE_BLOCK:PASS");
	}
}
