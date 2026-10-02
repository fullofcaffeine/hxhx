import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Checks that comments after Haxe value blocks cannot become JavaScript syntax.

	The same authored fixture runs through upstream Haxe and the Haxe-authored
	parser, typer, and JavaScript backend. Node checks the generated program against
	an independent expected result, including static and local initialization.
**/
class M14JsValueBlockIntegrationTest {
	static function deleteRecursive(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	/** Check token boundaries independently of the backend's source rendering. **/
	static function checkParserBoundaries():Void {
		final block = '{ var value:String = "}"; /* } */ value; }';
		for (suffix in [
			"",
			" \n",
			" /** next field */",
			" // next field",
			" /* first */ // second\n /** third */"
		]) {
			switch (HxParser.parseCompleteExprText(block + suffix)) {
				case ETryCatchRaw(raw):
					if (raw != "opaque_block_expr:" + block)
						throw "block source includes text outside its closing token: " + raw;
				case _:
					throw "typed source block must retain its local type annotation";
			}
		}
	}

	/** Require both initializer positions to reach the shared typed block representation. **/
	static function checkTypedBlocks(program:MacroExpandedProgram):Void {
		var staticBlock = false;
		var localBlock = false;
		for (module in program.getTypedModules())
			for (cls in module.getTypedClasses()) {
				for (initializer in cls.getFieldInitializers())
					if (initializer.getField().getName() == "initial")
						staticBlock = initializer.getExpression().getTag() == TypedExpr.TypedExprTag.Block;
				for (fn in cls.getFunctions())
					for (statement in fn.getBody().getStatements())
						if (statement.getNames().length > 0 && statement.getNames()[0] == "local" && statement.getExpressions().length == 1)
							localBlock = statement.getExpressions()[0].getTag() == TypedExpr.TypedExprTag.Block;
			}
		if (!staticBlock || !localBlock)
			throw "static and local value blocks must reach shared typing as Block nodes: static=" + staticBlock + ", local=" + localBlock;
	}

	static function run(command:String, args:Array<String>):String {
		final process = new sys.io.Process(command, args);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " exited " + code + ": " + stderr;
		return StringTools.trim(stdout);
	}

	static function main():Void {
		checkParserBoundaries();
		final fixtureDir = "test/fixtures/js_value_blocks";
		final fixturePath = Path.join([fixtureDir, "ValueBlocks.hx"]);
		final expected = "73\n42\n8\n4\n7342";
		final upstream = run("haxe", ["-cp", fixtureDir, "-main", "ValueBlocks", "--interp"]);
		if (upstream != expected)
			throw "upstream value-block result differs: " + upstream;

		final source = File.getContent(fixturePath);
		final parsed = ParserStage.parse(source, fixturePath);
		final resolved = new ResolvedModule("ValueBlocks", fixturePath, parsed);
		final index = TyperIndex.build([resolved]);
		final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index)], []);
		checkTypedBlocks(program);
		final outDir = Path.normalize(".tmp/m14_js_value_blocks_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(outDir);
		final artifactPath = Path.join([outDir, "main.js"]);
		new JsBackend().emit(program, new BackendContext(outDir, artifactPath, "ValueBlocks", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		run("node", ["--check", artifactPath]);
		final nativeOutput = run("node", [artifactPath]);
		if (nativeOutput != expected)
			throw "native value-block result differs: " + nativeOutput;
		deleteRecursive(outDir);
		Sys.println("JS_VALUE_BLOCK_RUNTIME:PASS");
	}
}
