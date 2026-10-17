import sys.io.File;

/** Recovered untyped blocks preserve counted-loop bounds and their original control destinations. */
class M14UntypedRangeRecoveryTest {
	public static function run():Void {
		final root = ".tmp/m14_untyped_range_recovery";
		sys.FileSystem.createDirectory(root);
		final body = 'var total:Dynamic=0;for(i in low()...high()){if(i==1)continue;if(i==3)break;total=total+i;}return total;';
		final source = 'class Main {static function low():Int{Sys.println("lower");return 0;}'
			+ 'static function high():Dynamic{Sys.println("upper");return 4;}'
			+ 'static function decode():Dynamic{untyped {'
			+ body
			+ '}}'
			+ 'static function main():Void{Sys.println(decode());}}';
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final expected = "lower\nupper\n2\n";
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "-main", "Main", "--interp"], expected: expected});
		Sys.println("UNTYPED_RANGE_UPSTREAM:PASS");
		final ordinary = ParserStage.parse(source, path);
		final position = HxPos.unknown();
		// Exercise the retained raw-block migration boundary with the same authored function body.
		final recovered = new HxFunctionDecl("decode", HxVisibility.Public, true, [], "Dynamic",
			[SExpr(EUntyped(ETryCatchRaw("opaque_block_expr:{" + body + "}")), position)], "", [], position);
		final methods = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(ordinary.getDecl()))
			.map(method -> HxFunctionDecl.getName(method) == "decode" ? recovered : method);
		final owner = new HxClassDecl("Main", true, methods, []);
		final parsed = new ParsedModule(source, new HxModuleDecl("", [], owner, [owner], false, false), path);
		final resolved = new ResolvedModule("Main", path, parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("UNTYPED_RANGE_JS:PASS");
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true, true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("UNTYPED_RANGE_NATIVE:PASS");
	}

	static function main():Void
		run();
}
