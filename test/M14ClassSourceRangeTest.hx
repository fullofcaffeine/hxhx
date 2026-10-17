import sys.io.File;
import hxhx.CompilationServerSourceCache;

/** Preserve real class positions through parsing and typed backend projection. */
class M14ClassSourceRangeTest {
	static function main():Void {
		final path = "test/fixtures/class_source_range/SourceClasses.hx";
		final source = File.getContent(path);
		final filtered = HxConditionalCompilation.filterSource(source, new haxe.ds.StringMap<String>());
		final parsed = new CompilerSourceProvider().parseFilteredSource({originalSource: source, filteredSource: filtered, filePath: path});
		final expected = ClassSourceRangeOracle.positions();
		check(HxModuleDecl.getClasses(parsed.getDecl()), expected, "parsed");
		final resolved = new ResolvedModule("SourceClasses", path, parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		check([for (cls in typed.getTypedClasses()) cls.getSourceDeclaration()], expected, "typed");
		check([for (cls in typed.getBackendProjection().getClasses()) cls.getDeclaration()], expected, "projected");
		if (HxClassDecl.getSourceRange(new HxClassDecl("Synthetic", false)) != null)
			throw "synthetic class invented a physical source range";
		checkCachedOriginalSource();
		var rejected = false;
		try
			ParserStage.parseFilteredSource({originalSource: source + " ", filteredSource: filtered, filePath: path})
		catch (_:String)
			rejected = true;
		if (!rejected)
			throw "parser accepted source with shifted string indices";
		Sys.println("CLASS_SOURCE_RANGE:PASS classes=5");
	}

	/** Equal filtered text must not hide edits to the original Unicode positions. */
	static function checkCachedOriginalSource():Void {
		final unicode = "#if false\n//é\n#end\nclass Main {}";
		final ascii = "#if false\n//" + StringTools.lpad("", "x", "é".length) + "\n#end\nclass Main {}";
		final filtered = HxConditionalCompilation.filterSource(unicode, new haxe.ds.StringMap<String>());
		if (filtered != HxConditionalCompilation.filterSource(ascii, new haxe.ds.StringMap<String>()))
			throw "cache regression requires equal filtered text";
		final cache = new CompilationServerSourceCache();
		var first:Null<ParsedModule> = null;
		for (step in 0...4) {
			final provider = cache.openRequest();
			final source = step == 2 ? ascii : unicode;
			final parsed = provider.parseFilteredSource({originalSource: source, filteredSource: filtered, filePath: "Main.hx"});
			// There are 18 ASCII characters before the class, plus the inactive letter.
			// The replacement has one ASCII character per original host-string unit.
			final start = step == 2 ? 18 + "é".length : 19;
			check(HxModuleDecl.getClasses(parsed.getDecl()), [{name: "Main", start: start, end: start + 13}], "cached step " + step);
			final expectedHit = step == 1 || step == 3;
			if (provider.report().parserHits != (expectedHit ? 1 : 0) || provider.report().parserMisses != (expectedHit ? 0 : 1))
				throw "parser cache reused a different original source or lost an unchanged source";
			if (step == 0)
				first = parsed;
			else if (step == 2 && parsed == first)
				throw "distinct original sources shared a cached declaration";
			provider.prepareFinish(true);
			provider.finish(true);
		}
		check(HxModuleDecl.getClasses(first.getDecl()), [{name: "Main", start: 19, end: 32}], "retained original");
	}

	/** The independent upstream ranges include the closing brace, but exclude trailing trivia. */
	static function check(classes:Array<HxClassDecl>, expected:Array<{name:String, start:Int, end:Int}>, phase:String):Void {
		for (row in expected) {
			final matches = classes.filter(cls -> HxClassDecl.getName(cls) == row.name);
			if (matches.length != 1)
				throw phase + " lost the exact source class " + row.name;
			final range = HxClassDecl.getSourceRange(matches[0]);
			if (range == null || range.start != row.start || range.end != row.end)
				throw phase + " class range differs from upstream for " + row.name;
		}
	}
}
